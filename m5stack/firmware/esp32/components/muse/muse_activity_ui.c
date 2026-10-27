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
#include "muse_timer.h"
#include "muse_ui.h"
#if CONFIG_MUSE_BOARD_M5STACK_CORES3
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
#if CONFIG_MUSE_BOARD_M5STACK_CORES3
static lv_obj_t *s_steps_btn, *s_steps_sub;
static lv_obj_t *s_squats_btn, *s_squats_sub;

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

static void on_mindful(lv_event_t *e)
{
    (void)e;
    muse_timer_start(60, "MINDFUL");
    go_face();
}

static void on_stretch(lv_event_t *e)
{
    (void)e;
    muse_timer_start(180, "STRETCH");
    go_face();
}

static void on_yoga(lv_event_t *e)
{
    (void)e;
    muse_timer_start(300, "YOGA");
    go_face();
}

static void on_health(lv_event_t *e)
{
    (void)e;
    muse_fit_check();
    go_face();
}

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
        paint_counter(s_steps_btn, s_steps_sub, muse_steps_active(), muse_steps_paused(),
                      muse_steps_count());
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
#endif
    if (s_health_sub) {
        char buf[20];
        muse_fit_today_t t;
        muse_fit_today(&t);
        if (t.score > 0) {
            snprintf(buf, sizeof(buf), "today %d", (int)t.score);
        } else {
            snprintf(buf, sizeof(buf), "diagnose");
        }
        if (strcmp(lv_label_get_text(s_health_sub), buf) != 0) {
            lv_label_set_text(s_health_sub, buf);
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

    int n = 4;
#if CONFIG_MUSE_BOARD_M5STACK_CORES3
    if (muse_squat_available()) {
        n = 6;
    }
#endif
    int cell_w = (muse_board->width - 16 - 8) / 2;
    int rows = (n + 1) / 2;
    int cell_h = (muse_board->height - 48 - 8 * (rows - 1)) / rows;
    if (cell_h < 56) {
        cell_h = 56;
    }

#if CONFIG_MUSE_BOARD_M5STACK_CORES3
    if (muse_squat_available()) {
        s_steps_btn = action_btn(grid, "Steps", "tap / hold=0", on_steps_tap, on_steps_hold,
                                 &s_steps_sub);
        lv_obj_set_size(s_steps_btn, cell_w, cell_h);
        s_squats_btn = action_btn(grid, "Squats", "tap / hold=0", on_squats_tap, on_squats_hold,
                                  &s_squats_sub);
        lv_obj_set_size(s_squats_btn, cell_w, cell_h);
    }
#endif
    lv_obj_t *mindful = action_btn(grid, "Mindful", "1 min", on_mindful, NULL, NULL);
    lv_obj_set_size(mindful, cell_w, cell_h);
    lv_obj_t *stretch = action_btn(grid, "Stretch", "3 min", on_stretch, NULL, NULL);
    lv_obj_set_size(stretch, cell_w, cell_h);
    lv_obj_t *yoga = action_btn(grid, "Yoga", "5 min", on_yoga, NULL, NULL);
    lv_obj_set_size(yoga, cell_w, cell_h);
    lv_obj_t *health = action_btn(grid, "Health", "diagnose", on_health, NULL, &s_health_sub);
    lv_obj_set_size(health, cell_w, cell_h);
}
