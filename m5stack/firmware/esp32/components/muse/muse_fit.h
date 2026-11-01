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

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "muse_pixel.h"

typedef struct {
    uint16_t squats;
    uint16_t steps;
    uint8_t mindful;
    uint8_t stretch;
    uint8_t yoga;
    uint8_t pets;    /* face pets today; 10 pets = 10 health points */
    uint8_t score;   /* 0..100, last check or live */
    uint8_t streak;  /* consecutive days at 60+ points */
} muse_fit_today_t;

void muse_fit_init(void);
void muse_fit_note_squat(void);
void muse_fit_note_step(void);
/* Add a finished walk's steps to today's total (1 health point per 10 steps). */
void muse_fit_note_steps(int n);
void muse_fit_note_timer(const char *name);
void muse_fit_note_pet(void);
void muse_fit_today(muse_fit_today_t *out);
int muse_fit_score(void);
int muse_fit_streak(void);
/* Overall grade for today's activity: "Good", "So so", or "Bad". */
const char *muse_fit_grade(void);
/* One-line next step that matches the grade. */
const char *muse_fit_advice(void);
/* Face diagnosis from today's stretch / mindful / yoga / squats / steps. */
void muse_fit_check(void);
bool muse_fit_active(void);
void muse_fit_tick(void);
void muse_fit_advance(void);
void muse_fit_fill_pose(muse_pose_t *pose);
