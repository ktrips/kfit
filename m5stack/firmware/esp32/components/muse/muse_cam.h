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

/* CoreS3 front camera: live preview, tap for 3-2-1, then snap to Muse. */

/* GO Camera button: start a preview, or start the 3-2-1 countdown if one is up. */
void muse_cam_toggle(void);
/* True while the live finder or countdown is on the face (a tap starts 3-2-1). */
bool muse_cam_preview_active(void);
/* Drop a live finder (e.g. Camera setting turned off). */
void muse_cam_stop(void);
/* Tap the finder: 3, 2, 1, then send the still to Muse. */
void muse_cam_snap(void);
/* Health: camera (if on), then Port B HR, then Muse diagnose. */
void muse_cam_health(void);
