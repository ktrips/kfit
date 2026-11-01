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

#include "driver/i2c_master.h"
#include "esp_err.h"

/*
 * CoreS3 BMI270: squat reps (held to the chest) and a pocket pedometer.
 * Short-press the GO button to start or pause; long-press to zero and exit.
 */

esp_err_t muse_squat_init(i2c_master_bus_handle_t bus);
bool muse_squat_available(void);

void muse_squat_set_active(bool on);   /* true = run, false = pause */
void muse_squat_toggle(void);
void muse_squat_exit_reset(void);      /* count = 0 and leave the mode */
bool muse_squat_active(void);          /* currently counting */
bool muse_squat_paused(void);
bool muse_squat_done(void);            /* hit the 20-rep goal */
int muse_squat_count(void);
int muse_squat_goal(void);
void muse_squat_reset(void);
/* 0 standing .. 1 at the bottom of a squat, smoothed. */
float muse_squat_bend(void);

void muse_steps_set_active(bool on);
void muse_steps_toggle(void);
void muse_steps_exit_reset(void);
bool muse_steps_active(void);
bool muse_steps_paused(void);
int muse_steps_count(void);
