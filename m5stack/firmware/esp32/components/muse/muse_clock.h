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
#include <time.h>

#include "driver/i2c_master.h"
#include "muse_pixel.h"
#include "muse_state.h"

/*
 * Local clock in JST. Wi-Fi starts SNTP (ntp.nict.jp); CoreS3 can also read
 * the BM8563 so the hour is known before the first sync.
 */

void muse_clock_init(void);
/* Optional: CoreS3 BM8563 on the internal I2C bus. */
void muse_clock_bind_rtc(i2c_master_bus_handle_t bus);
/* Start SNTP once Wi-Fi is up, and copy NTP back onto the RTC. */
void muse_clock_tick(void);
bool muse_clock_now(struct tm *out);
muse_tod_t muse_clock_tod(void);
/* Ask for a greeting after sleep (GOOD MORNING / GOOD NIGHT, …). */
void muse_clock_on_wake(void);
/* Idle caption only: never overwrites a reply, squat count or timer. */
void muse_clock_maybe_greet(muse_mode_t mode, bool busy);
