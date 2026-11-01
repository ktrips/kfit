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

#include "esp_err.h"

/*
 * CoreS3 Port B heart-rate: MAX30100/MAX30102 (I2C on G8/G9) or an analog
 * pulse sensor on G8. Press HR, keep a finger on the sensor until BPM.
 */

esp_err_t muse_hr_init(void);
void muse_hr_start(void);     /* GO button: start, or cancel if already running */
void muse_hr_begin(void);     /* start if idle (Health); no toggle */
void muse_hr_stop(void);
bool muse_hr_active(void);
int muse_hr_last_bpm(void);   /* 0 if none yet */
int muse_hr_live_bpm(void);   /* 0 while waiting */
