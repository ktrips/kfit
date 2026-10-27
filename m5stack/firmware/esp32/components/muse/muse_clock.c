/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing limitations under
 * the License.
 */

#include "muse_clock.h"

#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#include "esp_log.h"
#include "esp_sntp.h"
#include "esp_timer.h"

#include "muse_state.h"
#include "muse_wifi.h"

static const char *TAG = "muse_clock";

#define BM8563_ADDR 0x51
#define GREET_SECS 6.0f
#define GREET_EVERY_SECS 240.0f
#define MIN_YEAR 124   /* 2024 */

static i2c_master_dev_handle_t s_rtc;
static bool s_sntp;
static bool s_rtc_written;
static bool s_want_hello = true;
static muse_tod_t s_said_tod = MUSE_TOD_UNKNOWN;
static char s_said[48];
static int64_t s_said_until_us;
static int64_t s_next_hello_us;

static int bcd2(uint8_t v)
{
    return (v >> 4) * 10 + (v & 0x0f);
}

static uint8_t to_bcd(int v)
{
    return (uint8_t)(((v / 10) << 4) | (v % 10));
}

static bool year_ok(int tm_year)
{
    return tm_year >= MIN_YEAR;
}

static muse_tod_t tod_from_hour(int hour)
{
    if (hour < 5) {
        return MUSE_TOD_NIGHT;
    }
    if (hour < 11) {
        return MUSE_TOD_MORNING;
    }
    if (hour < 17) {
        return MUSE_TOD_DAY;
    }
    if (hour < 21) {
        return MUSE_TOD_EVENING;
    }
    return MUSE_TOD_LATE;
}

static const char *pick_line(muse_tod_t tod, int seed)
{
    static const char *const NIGHT[] = { "STILL UP?", "GO TO BED", "ZZZ...", "QUIET HOURS" };
    static const char *const MORNING[] = { "GOOD MORNING", "RISE AND SHINE", "LET'S GO", "YAWN... HI" };
    static const char *const DAY[] = { "GOOD AFTERNOON", "LUNCH TIME?", "KEEP GOING", "YOU GOT THIS" };
    static const char *const EVENING[] = { "GOOD EVENING", "NICE WORK TODAY", "WINDING DOWN", "STRETCH A BIT?" };
    static const char *const LATE[] = { "GOOD NIGHT", "SWEET DREAMS", "TIME TO REST", "SEE YOU TOMORROW" };
    const char *const *list = DAY;
    int n = 4;
    switch (tod) {
    case MUSE_TOD_NIGHT:
        list = NIGHT;
        break;
    case MUSE_TOD_MORNING:
        list = MORNING;
        break;
    case MUSE_TOD_DAY:
        list = DAY;
        break;
    case MUSE_TOD_EVENING:
        list = EVENING;
        break;
    case MUSE_TOD_LATE:
        list = LATE;
        break;
    default:
        return NULL;
    }
    return list[(seed < 0 ? 0 : seed) % n];
}

static esp_err_t rtc_rd(uint8_t reg, uint8_t *data, size_t n)
{
    return i2c_master_transmit_receive(s_rtc, &reg, 1, data, n, 50);
}

static esp_err_t rtc_wr(const uint8_t *data, size_t n)
{
    return i2c_master_transmit(s_rtc, data, n, 50);
}

static bool rtc_read(struct tm *out)
{
    if (!s_rtc) {
        return false;
    }
    uint8_t b[7];
    if (rtc_rd(0x02, b, sizeof(b)) != ESP_OK) {
        return false;
    }
    if (b[0] & 0x80) {
        return false;   /* VL: the oscillator has stopped */
    }
    memset(out, 0, sizeof(*out));
    out->tm_sec = bcd2(b[0] & 0x7f);
    out->tm_min = bcd2(b[1] & 0x7f);
    out->tm_hour = bcd2(b[2] & 0x3f);
    out->tm_mday = bcd2(b[3] & 0x3f);
    out->tm_wday = b[4] & 0x07;
    out->tm_mon = bcd2(b[5] & 0x1f) - 1;
    out->tm_year = bcd2(b[6]) + 100;   /* 20xx */
    if (!year_ok(out->tm_year) || out->tm_mon < 0 || out->tm_mon > 11) {
        return false;
    }
    return true;
}

static void rtc_write_tm(const struct tm *t)
{
    if (!s_rtc) {
        return;
    }
    uint8_t b[8] = {
        0x02,
        to_bcd(t->tm_sec),
        to_bcd(t->tm_min),
        to_bcd(t->tm_hour),
        to_bcd(t->tm_mday),
        (uint8_t)(t->tm_wday & 0x07),
        to_bcd(t->tm_mon + 1),
        to_bcd(t->tm_year % 100),
    };
    if (rtc_wr(b, sizeof(b)) == ESP_OK) {
        s_rtc_written = true;
    }
}

static void apply_rtc_to_system(void)
{
    struct tm t;
    if (!rtc_read(&t)) {
        return;
    }
    t.tm_isdst = -1;
    time_t sec = mktime(&t);
    if (sec < 0) {
        return;
    }
    struct timeval tv = { .tv_sec = sec };
    settimeofday(&tv, NULL);
    ESP_LOGI(TAG, "RTC %04d-%02d-%02d %02d:%02d JST", t.tm_year + 1900, t.tm_mon + 1, t.tm_mday,
             t.tm_hour, t.tm_min);
}

static void start_sntp(void)
{
    if (s_sntp || !muse_wifi_connected()) {
        return;
    }
    esp_sntp_setoperatingmode(ESP_SNTP_OPMODE_POLL);
    esp_sntp_setservername(0, "ntp.nict.jp");
    esp_sntp_setservername(1, "pool.ntp.org");
    esp_sntp_init();
    s_sntp = true;
    ESP_LOGI(TAG, "SNTP started");
}

void muse_clock_init(void)
{
    setenv("TZ", "JST-9", 1);
    tzset();
}

void muse_clock_bind_rtc(i2c_master_bus_handle_t bus)
{
    if (!bus || s_rtc) {
        return;
    }
    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = BM8563_ADDR,
        .scl_speed_hz = 400000,
    };
    if (i2c_master_bus_add_device(bus, &cfg, &s_rtc) != ESP_OK) {
        s_rtc = NULL;
        ESP_LOGW(TAG, "BM8563 missing");
        return;
    }
    uint8_t ctrl;
    if (rtc_rd(0x00, &ctrl, 1) != ESP_OK) {
        s_rtc = NULL;
        ESP_LOGW(TAG, "BM8563 not answering");
        return;
    }
    apply_rtc_to_system();
}

void muse_clock_tick(void)
{
    start_sntp();
    if (s_sntp && !s_rtc_written && s_rtc && muse_clock_now(NULL)) {
        struct tm t;
        if (muse_clock_now(&t)) {
            rtc_write_tm(&t);
        }
    }
}

bool muse_clock_now(struct tm *out)
{
    time_t sec = time(NULL);
    struct tm t;
    if (!localtime_r(&sec, &t) || !year_ok(t.tm_year)) {
        return false;
    }
    if (out) {
        *out = t;
    }
    return true;
}

muse_tod_t muse_clock_tod(void)
{
    struct tm t;
    if (!muse_clock_now(&t)) {
        return MUSE_TOD_UNKNOWN;
    }
    return tod_from_hour(t.tm_hour);
}

void muse_clock_on_wake(void)
{
    s_want_hello = true;
}

void muse_clock_maybe_greet(muse_mode_t mode, bool busy)
{
    int64_t now = esp_timer_get_time();
    struct tm t;
    if (!muse_clock_now(&t)) {
        return;
    }
    muse_tod_t tod = tod_from_hour(t.tm_hour);
    char cap[MUSE_CAPTION_MAX];
    muse_state_get_caption(cap, sizeof(cap));
    bool ours = s_said[0] && strcmp(cap, s_said) == 0;

    if (busy || mode != MUSE_MODE_IDLE) {
        return;
    }

    if (ours && now >= s_said_until_us) {
        s_said[0] = 0;
        muse_state_set_caption("%s", "");
        ours = false;
        cap[0] = 0;
    }

    bool period_changed = s_said_tod != MUSE_TOD_UNKNOWN && s_said_tod != tod;
    bool due = s_want_hello || period_changed || now >= s_next_hello_us;
    if (!due) {
        return;
    }

    /* Don't steal a reply, squat count or timer caption. */
    if (cap[0] && !ours) {
        s_want_hello = false;
        s_next_hello_us = now + (int64_t)(GREET_EVERY_SECS * 1e6f);
        return;
    }

    int seed = t.tm_yday * 24 + t.tm_hour + (int)(now / 1000000);
    const char *line = pick_line(tod, seed);
    if (!line) {
        return;
    }
    muse_state_set_caption("%s", line);
    strlcpy(s_said, line, sizeof(s_said));
    s_said_tod = tod;
    s_said_until_us = now + (int64_t)(GREET_SECS * 1e6f);
    s_next_hello_us = now + (int64_t)(GREET_EVERY_SECS * 1e6f);
    s_want_hello = false;
}
