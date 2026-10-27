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

#pragma once

#include <stdbool.h>

/*
 * Face countdown timers (mindfulness / stretch / yoga). The remaining time is
 * the caption; a fanfare plays when it ends. The home clock: tap to start or
 * pause, long-press to stop and clear.
 */

void muse_timer_start(int secs, const char *name);
/* Start `name` for `secs`, or pause / resume that same timer. */
void muse_timer_toggle(int secs, const char *name);
void muse_timer_stop(void);
/* Stop, drop the remaining time, no completion credit. */
void muse_timer_exit_reset(void);
bool muse_timer_active(void);
bool muse_timer_paused(void);
int muse_timer_remaining_s(void);
const char *muse_timer_label(void);
/* True if a tap dismissed the DONE banner. Running timers stay on the clock. */
bool muse_timer_on_face_tap(void);
