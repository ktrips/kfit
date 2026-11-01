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

#include "muse_activity_ui.h"

#include <stdio.h>
#include <string.h>

#include "lvgl.h"
#include "sdkconfig.h"

#include "muse_board.h"
#include "muse_fit.h"
#include "muse_settings.h"
#include "muse_timer.h"
#include "muse_ui.h"
#if CONFIG_MUSE_BOARD_M5STACK_CORES3
#include "muse_cam.h"
#include "muse_hr.h"
#include "muse_squat.h"
#endif

#define COLOR_TEXT 0xf2efff
#define COLOR_DIM 0x8b84a8
#define COLOR_CARD 0x1a1530
#define COLOR_CARD_PRESSED 0x2e2552
#define COLOR_CARD_ON 0x2a1f55
#define COLOR_CARD_PAUSE 0x241832
#define COLOR_ACCENT 0xa77dff

static void go_face(void)
{
    muse_ui_show_face();
}

static lv_obj_t *s_health_sub;
static lv_obj_t *s_timers_btn, *s_timers_sub;
static lv_obj_t *s_timer_pick;

#if CONFIG_MUSE_BOARD_M5STACK_CORES3
static lv_obj_t *s_steps_btn, *s_steps_sub;
static lv_obj_t *s_squats_btn, *s_squats_sub;
static lv_obj_t *s_camera_btn;
static lv_obj_t *s_hr_btn, *s_hr_sub;

static void on_hr(lv_event_t *e)
{
    (void)e;
    if (!muse_settings_hr_on()) {
        return;
    }
    muse_hr_start();
    go_face();
}

static void on_steps_tap(lv_event_t *e)
{
    (void)e;
    muse_steps_toggle();
    go_face();
}

static void on_steps_hold(lv_event_t *e)
{
    (void)e;
    muse_steps_exit_reset();
    go_face();
}

static void on_squats_tap(lv_event_t *e)
{
    (void)e;
    muse_squat_toggle();
    go_face();
}

static void on_squats_hold(lv_event_t *e)
{
    (void)e;
    muse_squat_exit_reset();
    go_face();
}
#endif

static void show_timer_pick(bool on)
{
    if (!s_timer_pick) {
        return;
    }
    lv_obj_set_flag(s_timer_pick, LV_OBJ_FLAG_HIDDEN, !on);
    muse_ui_set_swipe_enabled(!on);
}

static void pick_timer(int secs, const char *name)
{
    show_timer_pick(false);
    muse_timer_start(secs, name);
    go_face();
}

static void on_timers(lv_event_t *e)
{
    (void)e;
    show_timer_pick(true);
}

static void on_mindful(lv_event_t *e)
{
    (void)e;
    pick_timer(60, "MINDFUL");
}

static void on_stretch(lv_event_t *e)
{
    (void)e;
    pick_timer(180, "STRETCH");
}

static void on_yoga(lv_event_t *e)
{
    (void)e;
    pick_timer(300, "YOGA");
}

static void on_timer_back(lv_event_t *e)
{
    (void)e;
    show_timer_pick(false);
}

static void on_health(lv_event_t *e)
{
    (void)e;
    muse_fit_check();
    go_face();
}

#if CONFIG_MUSE_BOARD_M5STACK_CORES3
static void on_camera(lv_event_t *e)
{
    (void)e;
    if (!muse_settings_camera_on()) {
        return;
    }
    muse_cam_toggle();
}
#endif

static lv_obj_t *action_btn(lv_obj_t *grid, const char *title, const char *sub,
                            lv_event_cb_t on_tap, lv_event_cb_t on_hold, lv_obj_t **sub_out)
{
    lv_obj_t *b = lv_button_create(grid);
    lv_obj_remove_style_all(b);
    lv_obj_set_style_radius(b, 18, 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(b, lv_color_hex(COLOR_CARD), 0);
    lv_obj_set_style_bg_color(b, lv_color_hex(COLOR_CARD_PRESSED), LV_STATE_PRESSED);
    lv_obj_set_style_border_width(b, 2, 0);
    lv_obj_set_style_border_color(b, lv_color_hex(COLOR_CARD), 0);
    lv_obj_set_flex_flow(b, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(b, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(b, 4, 0);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_SCROLLABLE);
    if (on_tap) {
        lv_obj_add_event_cb(b, on_tap, LV_EVENT_SHORT_CLICKED, NULL);
    }
    if (on_hold) {
        lv_obj_add_event_cb(b, on_hold, LV_EVENT_LONG_PRESSED, NULL);
    }

    lv_obj_t *t = lv_label_create(b);
    lv_obj_set_style_text_font(t, &lv_font_montserrat_16, 0);
    lv_obj_set_style_text_color(t, lv_color_hex(COLOR_TEXT), 0);
    lv_obj_set_style_text_align(t, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_text(t, title);

    lv_obj_t *s = lv_label_create(b);
    lv_obj_set_style_text_font(s, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(s, lv_color_hex(COLOR_ACCENT), 0);
    lv_obj_set_style_text_align(s, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_text(s, sub ? sub : "");
    if (sub_out) {
        *sub_out = s;
    }
    return b;
}

static void paint_counter(lv_obj_t *btn, lv_obj_t *sub, bool running, bool paused, int count)
{
    if (!btn || !sub) {
        return;
    }
    char buf[24];
    uint32_t bg = COLOR_CARD;
    uint32_t border = COLOR_CARD;
    if (running) {
        snprintf(buf, sizeof(buf), "%d  on", count);
        bg = COLOR_CARD_ON;
        border = COLOR_ACCENT;
    } else if (paused) {
        snprintf(buf, sizeof(buf), "%d  paused", count);
        bg = COLOR_CARD_PAUSE;
        border = COLOR_DIM;
    } else {
        snprintf(buf, sizeof(buf), "tap / hold=0");
    }
    if (strcmp(lv_label_get_text(sub), buf) != 0) {
        lv_label_set_text(sub, buf);
    }
    lv_obj_set_style_bg_color(btn, lv_color_hex(bg), 0);
    lv_obj_set_style_border_color(btn, lv_color_hex(border), 0);
}

void muse_activity_ui_tick(void)
{
#if CONFIG_MUSE_BOARD_M5STACK_CORES3
    if (muse_squat_available()) {
        bool steps_on = muse_steps_active();
        bool steps_pause = muse_steps_paused();
        if (!steps_on && !steps_pause) {
            muse_fit_today_t t;
            muse_fit_today(&t);
            char buf[24];
            snprintf(buf, sizeof(buf), "today %d", (int)t.steps);
            if (s_steps_sub && strcmp(lv_label_get_text(s_steps_sub), buf) != 0) {
                lv_label_set_text(s_steps_sub, buf);
            }
            if (s_steps_btn) {
                lv_obj_set_style_bg_color(s_steps_btn, lv_color_hex(COLOR_CARD), 0);
                lv_obj_set_style_border_color(s_steps_btn, lv_color_hex(COLOR_CARD), 0);
            }
        } else {
            paint_counter(s_steps_btn, s_steps_sub, steps_on, steps_pause, muse_steps_count());
        }
        if (muse_squat_done()) {
            char buf[24];
            snprintf(buf, sizeof(buf), "%d/%d  done", muse_squat_count(), muse_squat_goal());
            if (s_squats_sub && strcmp(lv_label_get_text(s_squats_sub), buf) != 0) {
                lv_label_set_text(s_squats_sub, buf);
            }
            if (s_squats_btn) {
                lv_obj_set_style_bg_color(s_squats_btn, lv_color_hex(COLOR_CARD_ON), 0);
                lv_obj_set_style_border_color(s_squats_btn, lv_color_hex(COLOR_ACCENT), 0);
            }
        } else {
            paint_counter(s_squats_btn, s_squats_sub, muse_squat_active(), muse_squat_paused(),
                          muse_squat_count());
        }
    }
    if (s_camera_btn) {
        lv_obj_set_flag(s_camera_btn, LV_OBJ_FLAG_HIDDEN, !muse_settings_camera_on());
    }
    if (s_hr_btn) {
        lv_obj_set_flag(s_hr_btn, LV_OBJ_FLAG_HIDDEN, !muse_settings_hr_on());
    }
    if (s_hr_sub && muse_settings_hr_on()) {
        char buf[20];
        if (muse_hr_active()) {
            int live = muse_hr_live_bpm();
            if (live > 0) {
                snprintf(buf, sizeof(buf), "%d  …", live);
            } else {
                snprintf(buf, sizeof(buf), "finger on");
            }
        } else if (muse_hr_last_bpm() > 0) {
            snprintf(buf, sizeof(buf), "%d bpm", muse_hr_last_bpm());
        } else {
            snprintf(buf, sizeof(buf), "finger on");
        }
        if (strcmp(lv_label_get_text(s_hr_sub), buf) != 0) {
            lv_label_set_text(s_hr_sub, buf);
        }
        if (s_hr_btn) {
            uint32_t border = muse_hr_active() ? COLOR_ACCENT : COLOR_CARD;
            uint32_t bg = muse_hr_active() ? COLOR_CARD_ON : COLOR_CARD;
            lv_obj_set_style_bg_color(s_hr_btn, lv_color_hex(bg), 0);
            lv_obj_set_style_border_color(s_hr_btn, lv_color_hex(border), 0);
        }
    }
#endif
    if (s_health_sub) {
        char buf[20];
        muse_fit_today_t t;
        muse_fit_today(&t);
        if (t.score > 0 || t.steps > 0) {
            snprintf(buf, sizeof(buf), "H%d  %dst", (int)t.score, (int)t.steps);
        } else {
            snprintf(buf, sizeof(buf), "diagnose");
        }
        if (strcmp(lv_label_get_text(s_health_sub), buf) != 0) {
            lv_label_set_text(s_health_sub, buf);
        }
    }
    if (s_timers_sub) {
        char buf[24];
        if (muse_timer_active()) {
            const char *name = muse_timer_label();
            snprintf(buf, sizeof(buf), "%s %ds", name && name[0] ? name : "TIMER",
                     muse_timer_remaining_s());
        } else {
            snprintf(buf, sizeof(buf), "1 / 3 / 5 min");
        }
        if (strcmp(lv_label_get_text(s_timers_sub), buf) != 0) {
            lv_label_set_text(s_timers_sub, buf);
        }
        if (s_timers_btn) {
            uint32_t border = muse_timer_active() ? COLOR_ACCENT : COLOR_CARD;
            uint32_t bg = muse_timer_active() ? COLOR_CARD_ON : COLOR_CARD;
            lv_obj_set_style_bg_color(s_timers_btn, lv_color_hex(bg), 0);
            lv_obj_set_style_border_color(s_timers_btn, lv_color_hex(border), 0);
        }
    }
}

void muse_activity_ui_build(lv_obj_t *tile)
{
    lv_obj_set_style_bg_color(tile, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(tile, LV_OPA_COVER, 0);
    lv_obj_set_scrollbar_mode(tile, LV_SCROLLBAR_MODE_OFF);
    lv_obj_remove_flag(tile, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *title = lv_label_create(tile);
    lv_obj_set_style_text_font(title, &lv_font_montserrat_16, 0);
    lv_obj_set_style_text_color(title, lv_color_hex(COLOR_ACCENT), 0);
    lv_label_set_text(title, "GO");
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 10);

    lv_obj_t *grid = lv_obj_create(tile);
    lv_obj_remove_style_all(grid);
    lv_obj_set_size(grid, muse_board->width - 16, muse_board->height - 48);
    lv_obj_align(grid, LV_ALIGN_TOP_MID, 0, 36);
    lv_obj_set_style_pad_column(grid, 8, 0);
    lv_obj_set_style_pad_row(grid, 8, 0);
    lv_obj_set_flex_flow(grid, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_flex_align(grid, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_START);
    lv_obj_remove_flag(grid, LV_OBJ_FLAG_SCROLLABLE);

    int cols = 2;
    int n = 2;
#if CONFIG_MUSE_BOARD_M5STACK_CORES3
    n = muse_squat_available() ? 6 : 4;
#endif
    int cell_w = (muse_board->width - 16 - 8 * (cols - 1)) / cols;
    int rows = (n + cols - 1) / cols;
    int cell_h = (muse_board->height - 48 - 8 * (rows - 1)) / rows;
    if (cell_h < 56) {
        cell_h = 56;
    }

#if CONFIG_MUSE_BOARD_M5STACK_CORES3
    if (muse_squat_available()) {
        s_steps_btn = action_btn(grid, "Steps", "hold ends", on_steps_tap, on_steps_hold,
                                 &s_steps_sub);
        lv_obj_set_size(s_steps_btn, cell_w, cell_h);
        s_squats_btn = action_btn(grid, "Squats", "tap / hold=0", on_squats_tap, on_squats_hold,
                                  &s_squats_sub);
        lv_obj_set_size(s_squats_btn, cell_w, cell_h);
    }
    s_hr_btn = action_btn(grid, "HR", "finger on", on_hr, NULL, &s_hr_sub);
    lv_obj_set_size(s_hr_btn, cell_w, cell_h);
    if (!muse_settings_hr_on()) {
        lv_obj_add_flag(s_hr_btn, LV_OBJ_FLAG_HIDDEN);
    }
    s_camera_btn = action_btn(grid, "Camera", "photo", on_camera, NULL, NULL);
    lv_obj_set_size(s_camera_btn, cell_w, cell_h);
    if (!muse_settings_camera_on()) {
        lv_obj_add_flag(s_camera_btn, LV_OBJ_FLAG_HIDDEN);
    }
#endif
    s_timers_btn = action_btn(grid, "Timers", "1 / 3 / 5 min", on_timers, NULL, &s_timers_sub);
    lv_obj_set_size(s_timers_btn, cell_w, cell_h);
    lv_obj_t *health = action_btn(grid, "Health", "diagnose", on_health, NULL, &s_health_sub);
    lv_obj_set_size(health, cell_w, cell_h);

    s_timer_pick = lv_obj_create(tile);
    lv_obj_remove_style_all(s_timer_pick);
    lv_obj_set_size(s_timer_pick, lv_pct(100), lv_pct(100));
    lv_obj_set_style_bg_color(s_timer_pick, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(s_timer_pick, LV_OPA_COVER, 0);
    lv_obj_add_flag(s_timer_pick, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_HIDDEN);
    lv_obj_remove_flag(s_timer_pick, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *pick_title = lv_label_create(s_timer_pick);
    lv_obj_set_style_text_font(pick_title, &lv_font_montserrat_16, 0);
    lv_obj_set_style_text_color(pick_title, lv_color_hex(COLOR_ACCENT), 0);
    lv_label_set_text(pick_title, "TIMERS");
    lv_obj_align(pick_title, LV_ALIGN_TOP_MID, 0, 10);

    lv_obj_t *col = lv_obj_create(s_timer_pick);
    lv_obj_remove_style_all(col);
    lv_obj_set_size(col, muse_board->width - 24, muse_board->height - 48);
    lv_obj_align(col, LV_ALIGN_TOP_MID, 0, 36);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(col, LV_FLEX_ALIGN_SPACE_EVENLY, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(col, 8, 0);
    lv_obj_remove_flag(col, LV_OBJ_FLAG_SCROLLABLE);

    int pick_w = muse_board->width - 32;
    int pick_h = (muse_board->height - 48 - 24) / 4;
    if (pick_h < 40) {
        pick_h = 40;
    }
    lv_obj_t *mindful = action_btn(col, "Mindful", "1 min", on_mindful, NULL, NULL);
    lv_obj_set_size(mindful, pick_w, pick_h);
    lv_obj_t *stretch = action_btn(col, "Stretch", "3 min", on_stretch, NULL, NULL);
    lv_obj_set_size(stretch, pick_w, pick_h);
    lv_obj_t *yoga = action_btn(col, "Yoga", "5 min", on_yoga, NULL, NULL);
    lv_obj_set_size(yoga, pick_w, pick_h);
    lv_obj_t *back = action_btn(col, "Back", "", on_timer_back, NULL, NULL);
    lv_obj_set_size(back, pick_w, pick_h);
}
