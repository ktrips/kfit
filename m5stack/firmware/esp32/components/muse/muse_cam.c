/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/License-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing limitations under
 * the License.
 */

#include "muse_cam.h"

#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "bsp/m5stack_core_s3.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_video_device.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "linux/videodev2.h"

#include "muse_chat.h"
#include "muse_fit.h"
#include "muse_hr.h"
#include "muse_mem.h"
#include "muse_settings.h"
#include "muse_state.h"
#include "muse_ui.h"
#include "muse_voice.h"
#include "muse_wifi.h"

static const char *TAG = "muse_cam";

#define CAM_W 320
#define CAM_H 240
#define CAM_NBUF 2
#define JPEG_CAP (48 * 1024)

typedef enum { CAM_OFF, CAM_PREVIEW, CAM_COUNT, CAM_SNAP, CAM_HR } cam_state_t;

#define COUNT_MS 1000

static volatile cam_state_t s_state;
static volatile int s_count;
static TaskHandle_t s_task;
static bool s_inited;
static int s_fd = -1;
static uint8_t *s_map[CAM_NBUF];
static size_t s_map_len[CAM_NBUF];
static uint8_t *s_still;   /* last RGB565 BE frame, CAM_W * CAM_H * 2 */
static bool s_health_ask;
static char s_ask[640];

/* ---- Grayscale baseline JPEG (RGB565 BE in, one component out) ---- */

static const uint8_t s_zig[64] = {
    0,  1,  8, 16,  9,  2,  3, 10, 17, 24, 32, 25, 18, 11,  4,  5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13,  6,  7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63
};

static const uint8_t s_qt[64] = {
    16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55,
    14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
    18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
    49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99
};

/* Standard luminance DC/AC Huffman bits + values (ITU-T T.81 K.3). */
static const uint8_t s_dc_n[16] = { 0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0 };
static const uint8_t s_dc_v[12] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
static const uint8_t s_ac_n[16] = { 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d };
static const uint8_t s_ac_v[] = {
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
    0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
    0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
    0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa
};

typedef struct {
    uint16_t code[256];
    uint8_t size[256];
} huff_t;

static huff_t s_hdc, s_hac;
static bool s_huff_ok;

static void huff_build(huff_t *h, const uint8_t *nbits, const uint8_t *vals, int nval)
{
    memset(h, 0, sizeof(*h));
    uint16_t code = 0;
    int k = 0;
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < nbits[i]; j++) {
            uint8_t v = vals[k++];
            h->code[v] = code++;
            h->size[v] = (uint8_t)(i + 1);
        }
        code <<= 1;
    }
    (void)nval;
}

typedef struct {
    uint8_t *p, *end;
    uint32_t bit;
    int nbit;
} jw_t;

static bool jw_put(jw_t *w, const uint8_t *b, size_t n)
{
    if (w->p + n > w->end) {
        return false;
    }
    memcpy(w->p, b, n);
    w->p += n;
    return true;
}

static bool jw_byte(jw_t *w, uint8_t b)
{
    if (w->p >= w->end) {
        return false;
    }
    *w->p++ = b;
    if (b == 0xff && w->p < w->end) {
        *w->p++ = 0x00;
    }
    return true;
}

static bool jw_bits(jw_t *w, uint32_t bits, int n)
{
    w->bit = (w->bit << n) | (bits & ((1u << n) - 1));
    w->nbit += n;
    while (w->nbit >= 8) {
        w->nbit -= 8;
        if (!jw_byte(w, (uint8_t)(w->bit >> w->nbit))) {
            return false;
        }
    }
    return true;
}

static bool jw_huff(jw_t *w, const huff_t *h, uint8_t sym)
{
    return jw_bits(w, h->code[sym], h->size[sym]);
}

static bool jw_flush(jw_t *w)
{
    if (w->nbit) {
        if (!jw_bits(w, 0x7f, 8 - w->nbit)) {
            return false;
        }
    }
    return true;
}

static bool jw_marker(jw_t *w, uint8_t m, const uint8_t *d, uint16_t n)
{
    uint8_t hdr[4] = { 0xff, m, (uint8_t)((n + 2) >> 8), (uint8_t)(n + 2) };
    return jw_put(w, hdr, 4) && (n ? jw_put(w, d, n) : true);
}

static int category(int v)
{
    if (v < 0) {
        v = -v;
    }
    int c = 0;
    while (v) {
        v >>= 1;
        c++;
    }
    return c;
}

static uint32_t bits_of(int v, int cat)
{
    if (v < 0) {
        v--;
    }
    return (uint32_t)(v & ((1 << cat) - 1));
}

static void fdct(float *blk)
{
    float src[64];
    memcpy(src, blk, sizeof(src));
    const float pi = 3.141592653589793f;
    for (int v = 0; v < 8; v++) {
        for (int u = 0; u < 8; u++) {
            float s = 0;
            for (int y = 0; y < 8; y++) {
                for (int x = 0; x < 8; x++) {
                    s += src[y * 8 + x]
                         * cosf((2 * x + 1) * u * pi / 16.0f)
                         * cosf((2 * y + 1) * v * pi / 16.0f);
                }
            }
            float cu = u ? 1.0f : 0.7071067812f;
            float cv = v ? 1.0f : 0.7071067812f;
            blk[v * 8 + u] = 0.25f * cu * cv * s;
        }
    }
}

static uint8_t rgb565be_y(const uint8_t *p)
{
    unsigned v = ((unsigned)p[0] << 8) | p[1];
    unsigned r = (v >> 11) * 255 / 31;
    unsigned g = ((v >> 5) & 63) * 255 / 63;
    unsigned b = (v & 31) * 255 / 31;
    return (uint8_t)((77 * r + 150 * g + 29 * b) >> 8);
}

static bool encode_gray_jpeg(const uint8_t *rgb, uint8_t *out, size_t cap, size_t *len)
{
    if (!s_huff_ok) {
        huff_build(&s_hdc, s_dc_n, s_dc_v, 12);
        huff_build(&s_hac, s_ac_n, s_ac_v, (int)sizeof(s_ac_v));
        s_huff_ok = true;
    }
    jw_t w = { .p = out, .end = out + cap };
    static const uint8_t soi[] = { 0xff, 0xd8 };
    if (!jw_put(&w, soi, 2)) {
        return false;
    }
    uint8_t app0[] = { 'J', 'F', 'I', 'F', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0 };
    if (!jw_marker(&w, 0xe0, app0, sizeof(app0))) {
        return false;
    }
    uint8_t dqt[65];
    dqt[0] = 0x00;
    for (int i = 0; i < 64; i++) {
        dqt[1 + i] = s_qt[s_zig[i]];
    }
    if (!jw_marker(&w, 0xdb, dqt, 65)) {
        return false;
    }
    uint8_t sof[] = {
        8,
        (uint8_t)(CAM_H >> 8), (uint8_t)CAM_H,
        (uint8_t)(CAM_W >> 8), (uint8_t)CAM_W,
        1, 1, 0x11, 0
    };
    if (!jw_marker(&w, 0xc0, sof, sizeof(sof))) {
        return false;
    }
    uint8_t dht_dc[1 + 16 + 12];
    dht_dc[0] = 0x00;
    memcpy(dht_dc + 1, s_dc_n, 16);
    memcpy(dht_dc + 17, s_dc_v, 12);
    if (!jw_marker(&w, 0xc4, dht_dc, sizeof(dht_dc))) {
        return false;
    }
    uint8_t dht_ac[1 + 16 + sizeof(s_ac_v)];
    dht_ac[0] = 0x10;
    memcpy(dht_ac + 1, s_ac_n, 16);
    memcpy(dht_ac + 17, s_ac_v, sizeof(s_ac_v));
    if (!jw_marker(&w, 0xc4, dht_ac, sizeof(dht_ac))) {
        return false;
    }
    uint8_t sos[] = { 1, 1, 0x00, 0, 63, 0 };
    if (!jw_marker(&w, 0xda, sos, sizeof(sos))) {
        return false;
    }

    int prev_dc = 0;
    float blk[64];
    for (int by = 0; by < CAM_H; by += 8) {
        for (int bx = 0; bx < CAM_W; bx += 8) {
            for (int y = 0; y < 8; y++) {
                for (int x = 0; x < 8; x++) {
                    int xx = bx + x < CAM_W ? bx + x : CAM_W - 1;
                    int yy = by + y < CAM_H ? by + y : CAM_H - 1;
                    blk[y * 8 + x] = (float)rgb565be_y(rgb + ((size_t)yy * CAM_W + xx) * 2) - 128.0f;
                }
            }
            fdct(blk);
            int zz[64];
            for (int i = 0; i < 64; i++) {
                int z = s_zig[i];
                int q = s_qt[z] ? s_qt[z] : 1;
                zz[i] = (int)lrintf(blk[z] / (float)q);
            }
            int dc = zz[0] - prev_dc;
            prev_dc = zz[0];
            int cat = category(dc);
            if (!jw_huff(&w, &s_hdc, (uint8_t)cat) || (cat && !jw_bits(&w, bits_of(dc, cat), cat))) {
                return false;
            }
            int run = 0;
            for (int i = 1; i < 64; i++) {
                if (zz[i] == 0) {
                    run++;
                    continue;
                }
                while (run > 15) {
                    if (!jw_huff(&w, &s_hac, 0xf0)) {
                        return false;
                    }
                    run -= 16;
                }
                int ac = zz[i];
                cat = category(ac);
                if (!jw_huff(&w, &s_hac, (uint8_t)((run << 4) | cat))
                    || !jw_bits(&w, bits_of(ac, cat), cat)) {
                    return false;
                }
                run = 0;
            }
            if (run && !jw_huff(&w, &s_hac, 0x00)) {
                return false;
            }
        }
    }
    if (!jw_flush(&w)) {
        return false;
    }
    static const uint8_t eoi[] = { 0xff, 0xd9 };
    if (!jw_put(&w, eoi, 2)) {
        return false;
    }
    *len = (size_t)(w.p - out);
    return true;
}

/* ---- V4L2 capture ---- */

static void cam_close(void)
{
    int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (s_fd >= 0) {
        ioctl(s_fd, VIDIOC_STREAMOFF, &type);
        close(s_fd);
        s_fd = -1;
    }
    for (int i = 0; i < CAM_NBUF; i++) {
        s_map[i] = NULL;
        s_map_len[i] = 0;
    }
}

static bool cam_open(void)
{
    if (s_fd >= 0) {
        return true;
    }
    if (!s_inited) {
        bsp_camera_cfg_t cfg = { 0 };
        if (bsp_camera_start(&cfg) != ESP_OK) {
            ESP_LOGE(TAG, "bsp_camera_start");
            return false;
        }
        s_inited = true;
    }
    s_fd = open(BSP_CAMERA_DEVICE, O_RDWR);
    if (s_fd < 0) {
        ESP_LOGE(TAG, "open %s: %d", BSP_CAMERA_DEVICE, errno);
        return false;
    }
    struct v4l2_format fmt = {
        .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
        .fmt.pix = {
            .width = CAM_W,
            .height = CAM_H,
            .pixelformat = V4L2_PIX_FMT_RGB565X,
        },
    };
    if (ioctl(s_fd, VIDIOC_S_FMT, &fmt) != 0) {
        fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_RGB565;
        if (ioctl(s_fd, VIDIOC_S_FMT, &fmt) != 0) {
            ESP_LOGE(TAG, "S_FMT: %d", errno);
            cam_close();
            return false;
        }
    }
    struct v4l2_requestbuffers req = {
        .count = CAM_NBUF,
        .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
        .memory = V4L2_MEMORY_MMAP,
    };
    if (ioctl(s_fd, VIDIOC_REQBUFS, &req) != 0) {
        ESP_LOGE(TAG, "REQBUFS: %d", errno);
        cam_close();
        return false;
    }
    for (int i = 0; i < CAM_NBUF; i++) {
        struct v4l2_buffer buf = {
            .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
            .memory = V4L2_MEMORY_MMAP,
            .index = i,
        };
        if (ioctl(s_fd, VIDIOC_QUERYBUF, &buf) != 0) {
            cam_close();
            return false;
        }
        s_map[i] = mmap(NULL, buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, s_fd, buf.m.offset);
        s_map_len[i] = buf.length;
        if (s_map[i] == MAP_FAILED) {
            s_map[i] = NULL;
            cam_close();
            return false;
        }
        if (ioctl(s_fd, VIDIOC_QBUF, &buf) != 0) {
            cam_close();
            return false;
        }
    }
    int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (ioctl(s_fd, VIDIOC_STREAMON, &type) != 0) {
        ESP_LOGE(TAG, "STREAMON: %d", errno);
        cam_close();
        return false;
    }
    return true;
}

static bool grab_frame(void)
{
    struct v4l2_buffer buf = {
        .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
        .memory = V4L2_MEMORY_MMAP,
    };
    if (ioctl(s_fd, VIDIOC_DQBUF, &buf) != 0) {
        return false;
    }
    if ((buf.flags & V4L2_BUF_FLAG_DONE) && buf.index < CAM_NBUF && s_map[buf.index] && s_still) {
        size_t n = CAM_W * CAM_H * 2;
        if (buf.bytesused < n) {
            n = buf.bytesused;
        }
        memcpy(s_still, s_map[buf.index], n);
        muse_ui_image_draw(0, 0, CAM_W, CAM_H, (const uint16_t *)s_still);
    }
    return ioctl(s_fd, VIDIOC_QBUF, &buf) == 0;
}

static void fill_health_ask(bool with_face)
{
    muse_fit_today_t t;
    muse_fit_today(&t);
    int hr = muse_settings_hr_on() ? muse_hr_last_bpm() : 0;
    char hrbuf[16];
    if (hr > 0) {
        snprintf(hrbuf, sizeof(hrbuf), "%d bpm", hr);
    } else if (!muse_settings_hr_on()) {
        strlcpy(hrbuf, "off", sizeof(hrbuf));
    } else {
        strlcpy(hrbuf, "unknown", sizeof(hrbuf));
    }
    snprintf(s_ask, sizeof(s_ask),
             "%s Today: %d steps (1 health point per 10 steps), score %d/100 "
             "(goal 60), streak %d days, %d squats, mindful %d, stretch %d, "
             "yoga %d, pets %d, last heart rate %s. Reply with EXACTLY two lines, no markdown: "
             "line 1 only Good or So so or Bad for overall health; "
             "line 2 one short countermeasure in Japanese, at most 16 characters. "
             "日本語の対応策は短く。",
             with_face
                 ? "This is a selfie. Read the face (energy, tiredness, stress or calm) "
                   "together with today's activity."
                 : "No photo. Diagnose overall health from today's activity only.",
             (int)t.steps, (int)t.score, (int)t.streak, (int)t.squats, (int)t.mindful,
             (int)t.stretch, (int)t.yoga, (int)t.pets, hrbuf);
}

static void show_local_health(void)
{
    muse_state_set_caption("%s\n%s", muse_fit_grade(), muse_fit_advice());
}

static void measure_hr_blocking(void)
{
    if (!muse_settings_hr_on()) {
        return;
    }
    muse_ui_image_hide();
    muse_ui_countdown(0);
    muse_state_set_caption("心拍を測ります\n指を乗せて");
    muse_hr_begin();
    int64_t t0 = esp_timer_get_time();
    while (s_health_ask && muse_hr_active()) {
        if (esp_timer_get_time() - t0 > 40LL * 1000000) {
            muse_hr_stop();
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(80));
    }
}

static void show_local_health_now(void)
{
    int hr = muse_hr_last_bpm();
    if (hr > 0) {
        muse_state_set_caption("%s  %dbpm\n%s", muse_fit_grade(), hr, muse_fit_advice());
    } else {
        show_local_health();
    }
}

static void send_health(uint8_t *jpeg, size_t jlen)
{
    fill_health_ask(jpeg && jlen >= 64);
    s_health_ask = false;
    if (!muse_hatch_ready()) {
        free(jpeg);
        show_local_health_now();
        return;
    }
    muse_ui_image_hide();
    muse_state_set_caption("診断しています");
    muse_hatch_photo_turn_ask(jpeg, jlen, s_ask);
    muse_voice_await_photo_as("診断しています");
}

static void send_still(void)
{
    bool health = s_health_ask;
    uint8_t *jpeg = heap_caps_malloc(JPEG_CAP, MUSE_BIG_CAPS);
    size_t jlen = 0;
    if (!jpeg || !s_still || !encode_gray_jpeg(s_still, jpeg, JPEG_CAP, &jlen) || jlen < 64) {
        free(jpeg);
        jpeg = NULL;
        jlen = 0;
        if (!health) {
            s_health_ask = false;
            muse_state_set_caption("写真に失敗");
            return;
        }
    } else {
        ESP_LOGI(TAG, "jpeg %u bytes", (unsigned)jlen);
    }
    if (health) {
        s_state = CAM_HR;
        measure_hr_blocking();
        if (!s_health_ask) {
            free(jpeg);
            return;
        }
        send_health(jpeg, jlen);
        return;
    }
    s_health_ask = false;
    muse_state_set_caption("写真を送っています");
    if (!muse_hatch_ready()) {
        free(jpeg);
        muse_state_set_caption(muse_wifi_connected() ? "SET UP MUSE FIRST" : "NO WI-FI");
        return;
    }
    muse_ui_image_hide();
    muse_state_set_caption("Museに聞いています");
    muse_hatch_photo_turn_ask(jpeg, jlen, NULL);
    muse_voice_await_photo_as("Museを待っています");
}

static void ask_health_text(void)
{
    fill_health_ask(false);
    s_health_ask = false;
    muse_ui_image_hide();
    if (!muse_hatch_ready()) {
        show_local_health_now();
        return;
    }
    muse_hatch_photo_turn_ask(NULL, 0, s_ask);
    muse_voice_await_photo_as("診断しています");
}

static void show_finder_caption(void)
{
    if (s_health_ask) {
        muse_fit_today_t t;
        muse_fit_today(&t);
        muse_state_set_caption("歩数 %d  +%d\n画面をタップ", (int)t.steps, (int)t.steps / 10);
    } else {
        muse_state_set_caption("画面をタップ");
    }
}

static void cam_task(void *arg)
{
    (void)arg;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        if (s_state == CAM_HR) {
            measure_hr_blocking();
            if (s_health_ask) {
                ask_health_text();
            }
            s_state = CAM_OFF;
            continue;
        }
        if (s_state != CAM_PREVIEW) {
            continue;
        }
        if (!s_still) {
            s_still = heap_caps_malloc(CAM_W * CAM_H * 2, MUSE_BIG_CAPS);
        }
        if (!s_still || !cam_open()) {
            if (s_health_ask) {
                s_state = CAM_HR;
                measure_hr_blocking();
                if (s_health_ask) {
                    ask_health_text();
                }
            } else {
                muse_state_set_caption("NO CAMERA");
            }
            s_state = CAM_OFF;
            continue;
        }
        muse_state_set_asleep(false);
        show_finder_caption();
        int64_t count_us = 0;
        while (s_state == CAM_PREVIEW || s_state == CAM_COUNT) {
            grab_frame();
            if (s_state == CAM_COUNT) {
                int64_t now = esp_timer_get_time();
                if (count_us == 0) {
                    count_us = now;
                    muse_ui_countdown(s_count);
                } else if (now - count_us >= (int64_t)COUNT_MS * 1000) {
                    s_count--;
                    count_us = now;
                    if (s_count <= 0) {
                        muse_ui_countdown(0);
                        s_state = CAM_SNAP;
                        break;
                    }
                    muse_ui_countdown(s_count);
                }
            }
            vTaskDelay(pdMS_TO_TICKS(80));
        }
        if (s_state == CAM_SNAP) {
            grab_frame();
            int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
            ioctl(s_fd, VIDIOC_STREAMOFF, &type);
            cam_close();
            send_still();
            s_state = CAM_OFF;
        } else {
            cam_close();
        }
    }
}

static void ensure_task(void)
{
    if (s_task) {
        return;
    }
    if (xTaskCreatePinnedToCoreWithCaps(cam_task, "muse_cam", 8192, NULL, 5, &s_task,
                                        0, MUSE_BIG_CAPS) != pdPASS) {
        s_task = NULL;
        muse_state_set_caption("NO CAMERA");
    }
}

void muse_cam_toggle(void)
{
    if (!muse_settings_camera_on()) {
        muse_cam_stop();
        return;
    }
    muse_hr_stop();
    muse_ui_show_face();
    muse_state_set_asleep(false);
    if (s_state == CAM_PREVIEW) {
        muse_cam_snap();
        return;
    }
    if (s_state == CAM_COUNT || s_state == CAM_SNAP) {
        return;
    }
    s_health_ask = false;
    ensure_task();
    if (!s_task) {
        return;
    }
    s_state = CAM_PREVIEW;
    xTaskNotifyGive(s_task);
}

bool muse_cam_preview_active(void)
{
    return s_state == CAM_PREVIEW || s_state == CAM_COUNT;
}

void muse_cam_stop(void)
{
    if (s_state != CAM_OFF) {
        s_state = CAM_OFF;
        muse_ui_countdown(0);
        muse_ui_image_hide();
        muse_state_set_caption("%s", "");
    }
    if (s_health_ask) {
        s_health_ask = false;
        muse_hr_stop();
    }
}

void muse_cam_snap(void)
{
    if (s_state != CAM_PREVIEW) {
        return;
    }
    s_count = 3;
    s_state = CAM_COUNT;
    muse_state_set_caption("%s", "");
    muse_ui_countdown(3);
}

void muse_cam_health(void)
{
    if (s_health_ask && (s_state == CAM_PREVIEW || s_state == CAM_COUNT ||
                         s_state == CAM_SNAP || s_state == CAM_HR || muse_hr_active())) {
        return;
    }
    muse_hr_stop();
    muse_ui_show_face();
    muse_state_set_asleep(false);
    bool with_face = muse_settings_camera_on();
    s_health_ask = true;
    if (s_state == CAM_PREVIEW) {
        muse_cam_snap();
        return;
    }
    if (s_state == CAM_COUNT || s_state == CAM_SNAP) {
        return;
    }
    ensure_task();
    if (!s_task) {
        ask_health_text();
        return;
    }
    if (!with_face) {
        if (muse_settings_hr_on()) {
            s_state = CAM_HR;
            xTaskNotifyGive(s_task);
        } else {
            ask_health_text();
        }
        return;
    }
    s_state = CAM_PREVIEW;
    xTaskNotifyGive(s_task);
}
