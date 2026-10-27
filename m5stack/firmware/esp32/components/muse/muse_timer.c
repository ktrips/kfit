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
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "muse_timer.h"

#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "sdkconfig.h"

#include "muse_audio.h"
#include "muse_fit.h"
#include "muse_state.h"
#if CONFIG_MUSE_BOARD_M5STACK_CORES3
#include "muse_squat.h"
#endif

static const char *TAG = "muse_timer";

#define TICK_US 200000
#define DONE_HOLD_US (12LL * 1000000)

static esp_timer_handle_t s_tmr;
static bool s_ready;
static volatile bool s_active;
static int64_t s_end_us;
static int64_t s_done_until_us;
static char s_name[16];
static int s_last_shown = -1;
static int s_total_s;
static int s_buzzed;

static void show_remaining(int left)
{
    if (muse_fit_active() || muse_state_mode(NULL) != MUSE_MODE_IDLE) {
        return;
    }
    muse_state_set_caption("%s %d:%02d\nTAP TO STOP", s_name, left / 60, left % 60);
}

static void show_done(void)
{
    if (muse_fit_active() || muse_state_mode(NULL) != MUSE_MODE_IDLE) {
        return;
    }
    if (strcmp(s_name, "MINDFUL") == 0) {
        muse_state_set_caption("MINDFUL DONE\nYES!!!");
    } else if (strcmp(s_name, "STRETCH") == 0) {
        muse_state_set_caption("STRETCH DONE\nFEEL GREAT");
    } else if (strcmp(s_name, "YOGA") == 0) {
        muse_state_set_caption("YOGA DONE\nNAMASTE!");
    } else {
        muse_state_set_caption("%s DONE\nYOU DID IT", s_name);
    }
}

static void finish(void)
{
    s_active = false;
    if (s_tmr) {
        esp_timer_stop(s_tmr);
    }
    s_done_until_us = esp_timer_get_time() + DONE_HOLD_US;
    s_last_shown = -1;
    muse_fit_note_timer(s_name);
    show_done();
    muse_state_cheer();
    muse_audio_fanfare_async();
    ESP_LOGI(TAG, "%s done", s_name);
}

static void on_tick(void *arg)
{
    (void)arg;
    int64_t now = esp_timer_get_time();
    if (s_active) {
        int left = (int)((s_end_us - now + 999999) / 1000000);
        if (left <= 0) {
            finish();
            return;
        }
        muse_state_poke();
        if (left != s_last_shown) {
            s_last_shown = left;
            show_remaining(left);
            int elapsed = s_total_s - left;
            int marks = elapsed / 30;
            if (marks > s_buzzed) {
                s_buzzed = marks;
                muse_audio_tick_async();
            }
        }
        return;
    }
    if (s_done_until_us && now >= s_done_until_us) {
        s_done_until_us = 0;
        if (s_tmr) {
            esp_timer_stop(s_tmr);
        }
        if (muse_state_mode(NULL) == MUSE_MODE_IDLE) {
            muse_state_set_caption("%s", "");
        }
    }
}

static void ensure_timer(void)
{
    if (s_ready) {
        return;
    }
    const esp_timer_create_args_t t = {
        .callback = on_tick,
        .name = "face_timer",
    };
    if (esp_timer_create(&t, &s_tmr) == ESP_OK) {
        s_ready = true;
    }
}

void muse_timer_start(int secs, const char *name)
{
    if (secs <= 0 || !name || !name[0]) {
        return;
    }
    ensure_timer();
    if (!s_ready) {
        ESP_LOGW(TAG, "timer unavailable");
        return;
    }
#if CONFIG_MUSE_BOARD_M5STACK_CORES3
    if (muse_squat_active()) {
        muse_squat_set_active(false);
    }
    if (muse_steps_active()) {
        muse_steps_set_active(false);
    }
#endif
    strlcpy(s_name, name, sizeof(s_name));
    s_end_us = esp_timer_get_time() + (int64_t)secs * 1000000;
    s_done_until_us = 0;
    s_last_shown = -1;
    s_total_s = secs;
    s_buzzed = 0;
    s_active = true;
    esp_timer_stop(s_tmr);
    esp_timer_start_periodic(s_tmr, TICK_US);
    muse_state_poke();
    show_remaining(secs);
    muse_audio_tick_async();
    ESP_LOGI(TAG, "%s %ds", s_name, secs);
}

void muse_timer_stop(void)
{
    bool had = s_active || s_done_until_us;
    s_active = false;
    s_done_until_us = 0;
    s_last_shown = -1;
    if (s_tmr) {
        esp_timer_stop(s_tmr);
    }
    if (had && muse_state_mode(NULL) == MUSE_MODE_IDLE) {
        muse_state_set_caption("%s", "");
    }
}

bool muse_timer_active(void)
{
    return s_active;
}

int muse_timer_remaining_s(void)
{
    if (!s_active) {
        return 0;
    }
    int left = (int)((s_end_us - esp_timer_get_time() + 999999) / 1000000);
    return left > 0 ? left : 0;
}

const char *muse_timer_label(void)
{
    return s_name;
}

bool muse_timer_on_face_tap(void)
{
    if (s_active || s_done_until_us) {
        muse_timer_stop();
        return true;
    }
    return false;
}
