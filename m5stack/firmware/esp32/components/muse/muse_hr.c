/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing limitations under the License.
 */

#include "muse_hr.h"

#include <math.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_check.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "muse_mem.h"
#include "muse_settings.h"
#include "muse_state.h"
#include "muse_voice.h"

static const char *TAG = "muse_hr";

#define PORTB_SDA GPIO_NUM_8
#define PORTB_SCL GPIO_NUM_9
#define MAX3010X_ADDR 0x57
#define PART_MAX30100 0x11
#define PART_MAX30102 0x15
#define I2C_MS 20
#define SAMPLE_MS 20
#define FINGER_WAIT_MS 15000
#define HOLD_MS 10000
#define EARLY_MS 4000
#define FINGER_GONE_MS 4000
#define MIN_BEATS 4
#define MIN_BPM 40
#define MAX_BPM 180
#define MIN_RR_MS (60000 / MAX_BPM)
#define MAX_RR_MS (60000 / MIN_BPM)
#define RR_KEEP 10

typedef enum { SRC_NONE = 0, SRC_MAX30100, SRC_MAX30102, SRC_ANALOG } src_t;
typedef enum { ST_IDLE = 0, ST_WAIT, ST_HOLD, ST_DONE } st_t;

static src_t s_src;
static i2c_master_bus_handle_t s_bus;
static i2c_master_dev_handle_t s_dev;
static adc_oneshot_unit_handle_t s_adc;
static adc_channel_t s_adc_ch;
static TaskHandle_t s_task;
static SemaphoreHandle_t s_mu;
static volatile bool s_run;
static volatile st_t s_st;
static volatile int s_live_bpm;
static volatile int s_last_bpm;
static float s_lp, s_var, s_env;
static bool s_high;
static float s_peak;
static int64_t s_high_us;
static int64_t s_beat_us;
static int s_rr[RR_KEEP];
static int s_rr_n;
static int64_t s_start_us;
static int64_t s_hold_us;
static int64_t s_finger_us;

static esp_err_t wr(uint8_t reg, uint8_t val)
{
    if (!s_dev || !s_mu) {
        return ESP_ERR_INVALID_STATE;
    }
    uint8_t buf[2] = { reg, val };
    xSemaphoreTake(s_mu, portMAX_DELAY);
    esp_err_t err = i2c_master_transmit(s_dev, buf, sizeof(buf), I2C_MS);
    xSemaphoreGive(s_mu);
    return err;
}

static esp_err_t rd(uint8_t reg, uint8_t *data, size_t n)
{
    if (!s_dev || !s_mu) {
        return ESP_ERR_INVALID_STATE;
    }
    xSemaphoreTake(s_mu, portMAX_DELAY);
    esp_err_t err = i2c_master_transmit_receive(s_dev, &reg, 1, data, n, I2C_MS);
    xSemaphoreGive(s_mu);
    return err;
}

static int median_rr(void)
{
    if (s_rr_n <= 0) {
        return 0;
    }
    int t[RR_KEEP];
    memcpy(t, s_rr, (size_t)s_rr_n * sizeof(int));
    for (int i = 1; i < s_rr_n; i++) {
        int v = t[i], j = i;
        while (j > 0 && t[j - 1] > v) {
            t[j] = t[j - 1];
            j--;
        }
        t[j] = v;
    }
    return t[s_rr_n / 2];
}

static int bpm_from_rr(void)
{
    int rr = median_rr();
    if (rr < MIN_RR_MS || rr > MAX_RR_MS) {
        return 0;
    }
    return 60000 / rr;
}

static void det_reset(void)
{
    s_lp = 0;
    s_var = 0;
    s_env = 0;
    s_high = false;
    s_peak = 0;
    s_high_us = 0;
    s_beat_us = 0;
    s_rr_n = 0;
    s_live_bpm = 0;
}

static void note_sample(float x, int64_t now)
{
    if (s_lp == 0) {
        s_lp = x;
        return;
    }
    s_lp += (x - s_lp) * 0.08f;
    float d = x - s_lp;
    s_var += (d * d - s_var) * 0.03f;
    s_env += (fabsf(d) - s_env) * 0.05f;
    float rms = sqrtf(s_var < 0 ? 0 : s_var);
    float thr = rms * 0.7f;
    if (thr < 6.0f) {
        thr = 6.0f;
    }
    if (s_src == SRC_ANALOG && s_env > thr) {
        thr = s_env * 0.45f;
        if (thr < 8.0f) {
            thr = 8.0f;
        }
    }
    float off = thr * 0.35f;
    if (!s_high && d > thr) {
        s_high = true;
        s_peak = d;
        s_high_us = now;
    } else if (s_high) {
        if (d > s_peak) {
            s_peak = d;
        }
        int high_ms = (int)((now - s_high_us) / 1000);
        if (d < off) {
            s_high = false;
            int rr = s_beat_us ? (int)((now - s_beat_us) / 1000) : 0;
            s_beat_us = now;
            if (rr >= MIN_RR_MS && rr <= MAX_RR_MS) {
                if (s_rr_n < RR_KEEP) {
                    s_rr[s_rr_n++] = rr;
                } else {
                    memmove(s_rr, s_rr + 1, (RR_KEEP - 1) * sizeof(int));
                    s_rr[RR_KEEP - 1] = rr;
                }
                s_live_bpm = bpm_from_rr();
            }
            s_peak = 0;
        } else if (high_ms > MAX_RR_MS) {
            s_high = false;
            s_peak = 0;
        }
    }
}

static bool analog_read(float *out)
{
    int raw = 0;
    if (!s_adc || adc_oneshot_read(s_adc, s_adc_ch, &raw) != ESP_OK) {
        return false;
    }
    *out = (float)raw;
    return true;
}

static bool max_read_ir(float *out)
{
    uint8_t wrp = 0, rdp = 0, ist = 0;
    uint8_t ptr_wr = (s_src == SRC_MAX30102) ? 0x04 : 0x02;
    uint8_t ptr_rd = (s_src == SRC_MAX30102) ? 0x06 : 0x04;
    uint8_t fifo = (s_src == SRC_MAX30102) ? 0x07 : 0x05;
    /* Clear / check the data-ready flag so clones keep filling the FIFO. */
    (void)rd(0x00, &ist, 1);
    if (rd(ptr_wr, &wrp, 1) != ESP_OK || rd(ptr_rd, &rdp, 1) != ESP_OK) {
        return false;
    }
    int mask = (s_src == SRC_MAX30102) ? 0x1F : 0x0F;
    int n = (int)((wrp - rdp) & mask);
    if (n <= 0) {
        return false;
    }
    float last = 0;
    bool ok = false;
    int take = n > 4 ? 4 : n;
    for (int i = 0; i < take; i++) {
        uint8_t b[6];
        size_t need = s_src == SRC_MAX30102 ? 6 : 4;
        if (rd(fifo, b, need) != ESP_OK) {
            break;
        }
        uint32_t ir;
        if (s_src == SRC_MAX30102) {
            ir = ((uint32_t)b[3] << 16 | (uint32_t)b[4] << 8 | b[5]) & 0x3FFFF;
        } else {
            ir = ((uint32_t)b[0] << 8) | b[1];
        }
        last = (float)ir;
        ok = true;
    }
    if (ok) {
        *out = last;
    }
    return ok;
}

static bool sample(float *out)
{
    if (s_src == SRC_ANALOG) {
        return analog_read(out);
    }
    if (s_src == SRC_MAX30100 || s_src == SRC_MAX30102) {
        return max_read_ir(out);
    }
    return false;
}

static bool finger_ok(float x)
{
    if (s_src == SRC_MAX30102) {
        return x > 8000.0f;
    }
    if (s_src == SRC_MAX30100) {
        return x > 1500.0f;
    }
    return s_lp > 120.0f && s_lp < 4000.0f && s_env > 10.0f;
}

static void show_wait(int left_s)
{
    if (muse_state_mode(NULL) != MUSE_MODE_IDLE) {
        return;
    }
    muse_state_set_caption("HR\nFINGER ON  %ds", left_s);
}

static void show_hold(int bpm, int left_s)
{
    if (muse_state_mode(NULL) != MUSE_MODE_IDLE) {
        return;
    }
    if (bpm > 0) {
        muse_state_set_caption("HR %d\nHOLD  %ds", bpm, left_s);
    } else {
        muse_state_set_caption("HR\nHOLD STILL  %ds", left_s);
    }
}

static void leds_on(void);

static void finish(bool ok)
{
    int bpm = ok ? bpm_from_rr() : 0;
    s_run = false;
    s_st = ST_IDLE;
    s_live_bpm = bpm;
    if (bpm >= MIN_BPM && bpm <= MAX_BPM) {
        s_last_bpm = bpm;
        muse_state_set_caption("HR %d BPM", bpm);
        muse_state_make_happy();
        muse_voice_request_chirp();
        ESP_LOGI(TAG, "bpm %d from %d beats", bpm, s_rr_n);
    } else {
        muse_state_set_caption("HR\nNO PULSE");
        ESP_LOGW(TAG, "no pulse (%d beats src=%d)", s_rr_n, (int)s_src);
    }
    if (s_src == SRC_MAX30100 || s_src == SRC_MAX30102) {
        wr(s_src == SRC_MAX30102 ? 0x09 : 0x06, 0x80);
    }
}

static void leds_on(void)
{
    if (s_src == SRC_MAX30100) {
        wr(0x06, 0x40);           /* reset */
        vTaskDelay(pdMS_TO_TICKS(10));
        wr(0x06, 0x03);           /* SpO2+HR so IR+RED fill the FIFO */
        wr(0x07, 0x47);           /* 100 Hz, 1600 us, hi-res */
        wr(0x09, 0xBB);           /* IR/RED ~24 mA */
        wr(0x02, 0x00);
        wr(0x03, 0x00);
        wr(0x04, 0x00);
        wr(0x01, 0xF0);           /* interrupts */
    } else if (s_src == SRC_MAX30102) {
        wr(0x09, 0x40);           /* reset */
        vTaskDelay(pdMS_TO_TICKS(10));
        wr(0x08, 0x4F);
        wr(0x09, 0x03);           /* SpO2 mode: RED+IR FIFO */
        wr(0x0A, 0x27);           /* 100 Hz */
        wr(0x0C, 0x24);
        wr(0x0D, 0x24);
        wr(0x04, 0x00);
        wr(0x05, 0x00);
        wr(0x06, 0x00);
        wr(0x02, 0xC0);
    }
}

static void hr_task(void *arg)
{
    (void)arg;
    int64_t next_cap = 0;
    int64_t last_sample_us = 0;
    for (;;) {
        if (!s_run) {
            ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
            last_sample_us = 0;
            next_cap = 0;
            continue;
        }
        float x = 0;
        int64_t now = esp_timer_get_time();
        bool got = sample(&x);
        if (got) {
            last_sample_us = now;
            note_sample(x, now);
            if (finger_ok(x)) {
                if (s_st == ST_WAIT) {
                    s_st = ST_HOLD;
                    s_hold_us = now;
                    s_rr_n = 0;
                    s_beat_us = 0;
                    s_live_bpm = 0;
                    ESP_LOGI(TAG, "finger on  ir=%.0f", x);
                }
                s_finger_us = now;
            }
        } else if (s_src != SRC_ANALOG && last_sample_us &&
                   now - last_sample_us > (int64_t)1000 * 1000) {
            leds_on();
            last_sample_us = now;
        }

        if (s_st == ST_WAIT) {
            if (now - s_start_us > (int64_t)FINGER_WAIT_MS * 1000) {
                finish(false);
                continue;
            }
        } else if (s_st == ST_HOLD) {
            int held_ms = (int)((now - s_hold_us) / 1000);
            if (now - s_finger_us > (int64_t)FINGER_GONE_MS * 1000) {
                /* Finger lifted: go back to waiting instead of aborting. */
                s_st = ST_WAIT;
                s_start_us = now;
                s_rr_n = 0;
                s_live_bpm = 0;
                ESP_LOGI(TAG, "finger off, wait again");
            } else if (s_rr_n >= MIN_BEATS && held_ms >= EARLY_MS) {
                finish(true);
                continue;
            } else if (held_ms >= HOLD_MS) {
                finish(s_rr_n >= MIN_BEATS);
                continue;
            }
        }
        if (s_run && now >= next_cap) {
            next_cap = now + 400000;
            if (s_st == ST_WAIT) {
                int left = (int)((s_start_us + (int64_t)FINGER_WAIT_MS * 1000 - now) / 1000000);
                if (left < 1) {
                    left = 1;
                }
                show_wait(left);
            } else if (s_st == ST_HOLD) {
                int hold_left = (int)((s_hold_us + (int64_t)HOLD_MS * 1000 - now) / 1000000);
                if (hold_left < 1) {
                    hold_left = 1;
                }
                show_hold(s_live_bpm, hold_left);
            }
        }
        vTaskDelay(pdMS_TO_TICKS(SAMPLE_MS));
    }
}

static esp_err_t init_max(uint8_t part)
{
    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = MAX3010X_ADDR,
        .scl_speed_hz = 100000,
    };
    ESP_RETURN_ON_ERROR(i2c_master_bus_add_device(s_bus, &cfg, &s_dev), TAG, "add max3010x");
    s_src = part == PART_MAX30102 ? SRC_MAX30102 : SRC_MAX30100;
    wr(s_src == SRC_MAX30102 ? 0x09 : 0x06, 0x80);
    ESP_LOGI(TAG, "Port B %s at 0x57", s_src == SRC_MAX30102 ? "MAX30102" : "MAX30100");
    return ESP_OK;
}

static esp_err_t init_analog(void)
{
    adc_unit_t unit;
    ESP_RETURN_ON_ERROR(adc_oneshot_io_to_channel(PORTB_SDA, &unit, &s_adc_ch), TAG, "adc io");
    adc_oneshot_unit_init_cfg_t ucfg = { .unit_id = unit };
    ESP_RETURN_ON_ERROR(adc_oneshot_new_unit(&ucfg, &s_adc), TAG, "adc unit");
    adc_oneshot_chan_cfg_t ccfg = {
        .bitwidth = ADC_BITWIDTH_12,
        .atten = ADC_ATTEN_DB_12,
    };
    ESP_RETURN_ON_ERROR(adc_oneshot_config_channel(s_adc, s_adc_ch, &ccfg), TAG, "adc ch");
    s_src = SRC_ANALOG;
    ESP_LOGI(TAG, "Port B analog pulse on GPIO%d", (int)PORTB_SDA);
    return ESP_OK;
}

static bool try_max(void)
{
    /* CoreS3 BSP already owns I2C_NUM_1 (AXP/AW9523/touch). Opening it
     * again corrupts that bus and the display never comes up. */
    i2c_master_bus_config_t bus = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = PORTB_SDA,
        .scl_io_num = PORTB_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    if (i2c_new_master_bus(&bus, &s_bus) != ESP_OK) {
        s_bus = NULL;
        return false;
    }
    bool ack = false;
    for (int i = 0; i < 4 && !ack; i++) {
        ack = i2c_master_probe(s_bus, MAX3010X_ADDR, 100) == ESP_OK;
        if (!ack) {
            vTaskDelay(pdMS_TO_TICKS(20));
        }
    }
    if (!ack) {
        i2c_del_master_bus(s_bus);
        s_bus = NULL;
        return false;
    }
    uint8_t part = PART_MAX30100;
    i2c_device_config_t probe_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = MAX3010X_ADDR,
        .scl_speed_hz = 100000,
    };
    if (i2c_master_bus_add_device(s_bus, &probe_cfg, &s_dev) == ESP_OK) {
        uint8_t id = 0;
        if (rd(0xFF, &id, 1) == ESP_OK && (id == PART_MAX30100 || id == PART_MAX30102)) {
            part = id;
        }
        i2c_master_bus_rm_device(s_dev);
        s_dev = NULL;
    }
    if (init_max(part) != ESP_OK) {
        i2c_del_master_bus(s_bus);
        s_bus = NULL;
        s_src = SRC_NONE;
        return false;
    }
    return true;
}

static bool ensure_hw(void)
{
    if (s_src != SRC_NONE) {
        return true;
    }
    if (try_max()) {
        return true;
    }
    return init_analog() == ESP_OK;
}

static void begin_run(void)
{
    muse_state_set_asleep(false);
    muse_state_poke();
    det_reset();
    s_last_bpm = 0;
    s_start_us = esp_timer_get_time();
    s_finger_us = s_start_us;
    s_st = ST_WAIT;
    leds_on();
    s_run = true;
    xTaskNotifyGive(s_task);
    show_wait(FINGER_WAIT_MS / 1000);
}

esp_err_t muse_hr_init(void)
{
    /* Hardware is opened on first HR press. Touching I2C at boot breaks the
     * CoreS3 expander and the screen never starts. */
    if (!s_mu) {
        s_mu = xSemaphoreCreateMutex();
        if (!s_mu) {
            return ESP_ERR_NO_MEM;
        }
    }
    if (s_task) {
        return ESP_OK;
    }
    if (xTaskCreatePinnedToCore(hr_task, "hr", 4096, NULL, MUSE_UI_PRIORITY - 1,
                                &s_task, MUSE_UI_CORE ? 0 : 1) != pdPASS) {
        ESP_LOGE(TAG, "HR task");
        s_task = NULL;
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

void muse_hr_stop(void)
{
    s_run = false;
    s_st = ST_IDLE;
    if (s_src == SRC_MAX30100 || s_src == SRC_MAX30102) {
        wr(s_src == SRC_MAX30102 ? 0x09 : 0x06, 0x80);
    }
}

void muse_hr_begin(void)
{
    if (!muse_settings_hr_on()) {
        return;
    }
    if (!s_task) {
        muse_state_set_caption("HR\nNO SENSOR");
        return;
    }
    if (s_run) {
        return;
    }
    if (!ensure_hw()) {
        muse_state_set_caption("HR\nNO SENSOR");
        return;
    }
    begin_run();
}

void muse_hr_start(void)
{
    if (!muse_settings_hr_on()) {
        return;
    }
    if (!s_task) {
        muse_state_set_caption("HR\nNO SENSOR");
        return;
    }
    if (s_run) {
        muse_hr_stop();
        muse_state_set_caption("HR\nCANCELED");
        return;
    }
    if (!ensure_hw()) {
        muse_state_set_caption("HR\nNO SENSOR");
        return;
    }
    begin_run();
}

bool muse_hr_active(void)
{
    return s_run;
}

int muse_hr_last_bpm(void)
{
    return s_last_bpm;
}

int muse_hr_live_bpm(void)
{
    return s_live_bpm;
}
