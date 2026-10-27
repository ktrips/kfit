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

#include "muse_fit.h"

#include <string.h>

#include "esp_log.h"
#include "esp_timer.h"
#include "nvs.h"

#include "muse_audio.h"
#include "muse_board.h"
#include "muse_clock.h"
#include "muse_settings.h"
#include "muse_state.h"
#include "muse_timer.h"

static const char *TAG = "muse_fit";

#define MAGIC_V1 0x46495431u   /* FIT1 */
#define MAGIC_V2 0x46495432u   /* FIT2: pets */
#define MAGIC 0x46495433u      /* FIT3: streak */
#define GOAL_PTS 60
#define SCAN_MS 1400
#define PAGE_MS 3800
#define TIP_MS 3200
#define LOOK_SCAN 0.0f
#define LOOK_GOOD 1.0f
#define LOOK_LOW 2.0f
#define LOOK_CALM 3.0f
#define LOOK_STRONG 4.0f
#define LOOK_WALK 5.0f

typedef struct {
    uint32_t magic;
    uint32_t day;
    uint16_t squats;
    uint16_t steps;
    uint8_t mindful;
    uint8_t stretch;
    uint8_t yoga;
    uint8_t last_score;
} blob_v1_t;

typedef struct {
    uint32_t magic;
    uint32_t day;
    uint16_t squats;
    uint16_t steps;
    uint8_t mindful;
    uint8_t stretch;
    uint8_t yoga;
    uint8_t last_score;
    uint8_t pets;
} blob_v2_t;

typedef struct {
    uint32_t magic;
    uint32_t day;
    uint16_t squats;
    uint16_t steps;
    uint8_t mindful;
    uint8_t stretch;
    uint8_t yoga;
    uint8_t last_score;
    uint8_t pets;
    uint8_t streak;
    uint32_t last_ok_day;
} blob_t;

static blob_t s;
static nvs_handle_t s_nvs;
static bool s_ok;
static int s_unsaved_steps;
static int s_page = -1;
static int64_t s_page_until_us;
static float s_look;

static int score_now(void);

static uint32_t day_id(void)
{
    struct tm t;
    if (muse_clock_now(&t)) {
        return ((uint32_t)t.tm_year << 16) | (uint16_t)t.tm_yday;
    }
    return 0;
}

static bool day_follows(uint32_t earlier, uint32_t later)
{
    if (!earlier || !later) {
        return false;
    }
    uint16_t y0 = (uint16_t)(earlier >> 16), d0 = (uint16_t)(earlier & 0xffff);
    uint16_t y1 = (uint16_t)(later >> 16), d1 = (uint16_t)(later & 0xffff);
    if (y0 == y1 && d1 == d0 + 1) {
        return true;
    }
    return y1 == y0 + 1 && d1 == 0 && d0 >= 364;
}

static void note_streak(void)
{
    if (score_now() < GOAL_PTS) {
        return;
    }
    uint32_t d = s.day ? s.day : day_id();
    if (!d || s.last_ok_day == d) {
        return;
    }
    if (day_follows(s.last_ok_day, d)) {
        if (s.streak < 250) {
            s.streak++;
        }
    } else {
        s.streak = 1;
    }
    s.last_ok_day = d;
    ESP_LOGI(TAG, "goal day %u streak %u", (unsigned)d, s.streak);
}

static void roll(void)
{
    uint32_t d = day_id();
    if (s.day == 0 && d != 0) {
        s.day = d;
        return;
    }
    if (d != 0 && s.day != 0 && d != s.day) {
        if (s.last_ok_day != s.day) {
            s.streak = 0;
        }
        s.squats = 0;
        s.steps = 0;
        s.mindful = 0;
        s.stretch = 0;
        s.yoga = 0;
        s.last_score = 0;
        s.pets = 0;
        s.day = d;
        ESP_LOGI(TAG, "new day streak %u", s.streak);
    } else if (s.day == 0) {
        s.day = d;
    }
}

static void save(void)
{
    if (!s_ok) {
        return;
    }
    s.magic = MAGIC;
    nvs_set_blob(s_nvs, "day", &s, sizeof(s));
    nvs_commit(s_nvs);
}

static int score_now(void)
{
    int sc = 0;
    sc += s.mindful * 22;
    if (sc > 44) {
        sc = 44;
    }
    int st = s.stretch * 16;
    if (st > 32) {
        st = 32;
    }
    sc += st;
    int yg = s.yoga * 22;
    if (yg > 44) {
        yg = 44;
    }
    sc += yg;
    int sq = s.squats;
    if (sq > 30) {
        sq = 30;
    }
    sc += sq;
    int wp = s.steps / 160;
    if (wp > 28) {
        wp = 28;
    }
    sc += wp;
    int pt = s.pets;
    if (pt > 20) {
        pt = 20;
    }
    sc += pt;
    if (sc > 100) {
        sc = 100;
    }
    return sc;
}

static const char *headline(int sc)
{
    if (sc >= 80) {
        return "PEAK FORM";
    }
    if (sc >= 60) {
        return "STRONG DAY";
    }
    if (sc >= 40) {
        return "BALANCED";
    }
    if (sc >= 20) {
        return "GETTING THERE";
    }
    if (sc > 0) {
        return "LOW ENERGY";
    }
    return "REST DAY?";
}

static void pick_look(int sc)
{
    if (sc >= 60 && s.squats >= 12) {
        s_look = LOOK_STRONG;
    } else if (sc >= 50) {
        s_look = LOOK_GOOD;
    } else if (s.mindful || s.yoga) {
        s_look = LOOK_CALM;
    } else if (s.steps >= 800) {
        s_look = LOOK_WALK;
    } else if (sc >= 20) {
        s_look = LOOK_GOOD;
    } else {
        s_look = LOOK_LOW;
    }
}

static const char *tip(void)
{
    if (s.mindful == 0 && s.stretch == 0 && s.yoga == 0 && s.squats == 0 && s.steps < 200) {
        return "TRY 1 MIN\nMINDFUL";
    }
    if (s.mindful == 0) {
        return "ADD MINDFUL\nFOR CALM";
    }
    if (s.stretch == 0 && s.yoga == 0) {
        return "STRETCH 3 MIN\nFOR MOBILITY";
    }
    if (s.squats < 8 && s.steps < 1200) {
        return "MOVE A BIT\nSTEPS OR SQUATS";
    }
    if (s.steps < 1500 && s.squats >= 8) {
        return "A WALK NEXT\nFOR CARDIO";
    }
    if (s.yoga == 0 && s.stretch) {
        return "YOGA 5 MIN\nTO UNWIND";
    }
    return "REST WELL\nSEE YOU TOMORROW";
}

static void show_page(int page)
{
    int sc = s.last_score;
    switch (page) {
    case 0:
        muse_state_set_caption("CHECKING...\nTODAY");
        s_look = LOOK_SCAN;
        s_page_until_us = esp_timer_get_time() + (int64_t)SCAN_MS * 1000;
        break;
    case 1:
        muse_state_set_caption("HEALTH %d\n%s", sc, headline(sc));
        pick_look(sc);
        if (sc >= 50) {
            muse_state_make_happy();
        }
        if (muse_board->audio_init && muse_settings_speaker_on()) {
            muse_audio_power(true);
            muse_audio_chirp(sc >= 50);
        }
        s_page_until_us = esp_timer_get_time() + (int64_t)PAGE_MS * 1000;
        break;
    case 2:
        muse_state_set_caption("SQ %d  ST %d\nM%d T%d Y%d", (int)s.squats, (int)s.steps,
                               (int)s.mindful, (int)s.stretch, (int)s.yoga);
        s_page_until_us = esp_timer_get_time() + (int64_t)PAGE_MS * 1000;
        break;
    case 3:
        muse_state_set_caption("%s", tip());
        s_page_until_us = esp_timer_get_time() + (int64_t)TIP_MS * 1000;
        break;
    default:
        s_page = -1;
        if (muse_state_mode(NULL) == MUSE_MODE_IDLE) {
            muse_state_set_caption("%s", "");
        }
        break;
    }
}

void muse_fit_init(void)
{
    if (nvs_open("musefit", NVS_READWRITE, &s_nvs) != ESP_OK) {
        ESP_LOGW(TAG, "NVS open failed");
        return;
    }
    memset(&s, 0, sizeof(s));
    size_t n = sizeof(s);
    esp_err_t err = nvs_get_blob(s_nvs, "day", &s, &n);
    if (err == ESP_OK && s.magic == MAGIC && n >= sizeof(s)) {
        /* current blob */
    } else if (err == ESP_OK && s.magic == MAGIC_V2) {
        s.streak = 0;
        s.last_ok_day = 0;
        s.magic = MAGIC;
        s_ok = true;
        save();
    } else {
        blob_v2_t v2;
        size_t n2 = sizeof(v2);
        blob_v1_t v1;
        size_t n1 = sizeof(v1);
        memset(&s, 0, sizeof(s));
        if (nvs_get_blob(s_nvs, "day", &v2, &n2) == ESP_OK && v2.magic == MAGIC_V2) {
            s.day = v2.day;
            s.squats = v2.squats;
            s.steps = v2.steps;
            s.mindful = v2.mindful;
            s.stretch = v2.stretch;
            s.yoga = v2.yoga;
            s.last_score = v2.last_score;
            s.pets = v2.pets;
        } else if (nvs_get_blob(s_nvs, "day", &v1, &n1) == ESP_OK && v1.magic == MAGIC_V1) {
            s.day = v1.day;
            s.squats = v1.squats;
            s.steps = v1.steps;
            s.mindful = v1.mindful;
            s.stretch = v1.stretch;
            s.yoga = v1.yoga;
            s.last_score = v1.last_score;
        }
        s.magic = MAGIC;
        s_ok = true;
        save();
    }
    s_ok = true;
    roll();
    note_streak();
    ESP_LOGI(TAG, "today SQ %u ST %u M%d T%d Y%d P%d *%u", s.squats, s.steps, s.mindful, s.stretch,
             s.yoga, s.pets, s.streak);
}

void muse_fit_note_squat(void)
{
    roll();
    if (s.squats < 40000) {
        s.squats++;
        note_streak();
        save();
    }
}

void muse_fit_note_step(void)
{
    roll();
    if (s.steps < 60000) {
        s.steps++;
        uint8_t was = s.streak;
        note_streak();
        if (s.streak != was || ++s_unsaved_steps >= 10) {
            s_unsaved_steps = 0;
            save();
        }
    }
}

void muse_fit_note_timer(const char *name)
{
    if (!name) {
        return;
    }
    roll();
    if (strcmp(name, "MINDFUL") == 0 && s.mindful < 20) {
        s.mindful++;
    } else if (strcmp(name, "STRETCH") == 0 && s.stretch < 20) {
        s.stretch++;
    } else if (strcmp(name, "YOGA") == 0 && s.yoga < 20) {
        s.yoga++;
    } else {
        return;
    }
    note_streak();
    save();
}

void muse_fit_note_pet(void)
{
    roll();
    if (s.pets < 40) {
        s.pets++;
        note_streak();
        save();
    }
}

void muse_fit_today(muse_fit_today_t *out)
{
    if (!out) {
        return;
    }
    roll();
    out->squats = s.squats;
    out->steps = s.steps;
    out->mindful = s.mindful;
    out->stretch = s.stretch;
    out->yoga = s.yoga;
    out->pets = s.pets;
    out->score = (uint8_t)score_now();
    out->streak = s.streak;
}

int muse_fit_streak(void)
{
    roll();
    return (int)s.streak;
}

int muse_fit_score(void)
{
    roll();
    return s.last_score ? (int)s.last_score : score_now();
}

void muse_fit_check(void)
{
    roll();
    if (s_unsaved_steps) {
        s_unsaved_steps = 0;
        save();
    }
    muse_timer_stop();
    s.last_score = (uint8_t)score_now();
    note_streak();
    save();
    s_page = 0;
    show_page(0);
    muse_state_poke();
    ESP_LOGI(TAG, "health %d SQ %u ST %u M%d T%d Y%d", s.last_score, s.squats, s.steps,
             s.mindful, s.stretch, s.yoga);
}

bool muse_fit_active(void)
{
    return s_page >= 0;
}

void muse_fit_tick(void)
{
    if (s_page < 0) {
        return;
    }
    if (esp_timer_get_time() < s_page_until_us) {
        muse_state_poke();
        return;
    }
    s_page++;
    if (s_page > 3) {
        s_page = -1;
        if (muse_state_mode(NULL) == MUSE_MODE_IDLE) {
            muse_state_set_caption("%s", "");
        }
        return;
    }
    show_page(s_page);
}

void muse_fit_advance(void)
{
    if (s_page < 0) {
        return;
    }
    s_page_until_us = 0;
    muse_fit_tick();
}

void muse_fit_fill_pose(muse_pose_t *pose)
{
    if (!pose || s_page < 0) {
        return;
    }
    pose->move = MUSE_MOVE_HEALTH;
    pose->move_t = s_look;
    if (s_look == LOOK_CALM) {
        pose->move = MUSE_MOVE_MINDFUL;
    } else if (s_look == LOOK_WALK) {
        pose->move = MUSE_MOVE_WALK;
    } else if (s_look == LOOK_STRONG) {
        pose->move = MUSE_MOVE_SQUAT;
        pose->move_t = 0.25f;
    }
}
