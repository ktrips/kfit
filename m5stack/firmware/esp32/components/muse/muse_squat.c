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

#include "muse_squat.h"

#include <math.h>
#include <string.h>

#include "esp_check.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "muse_audio.h"
#include "muse_fit.h"
#include "muse_hr.h"
#include "muse_mem.h"
#include "muse_state.h"
#include "muse_timer.h"

static const char *TAG = "muse_squat";

#define BMI270_ADDR 0x69
#define BMI270_ADDR_ALT 0x68
#define CHIP_ID 0x24
#define REG_CHIP_ID 0x00
#define REG_ACC_X_LSB 0x0C
#define REG_INTERNAL_STATUS 0x21
#define REG_ACC_CONF 0x40
#define REG_ACC_RANGE 0x41
#define REG_INIT_CTRL 0x59
#define REG_INIT_ADDR_0 0x5B
#define REG_INIT_DATA 0x5E
#define REG_PWR_CONF 0x7C
#define REG_PWR_CTRL 0x7D
#define REG_CMD 0x7E
#define CMD_SOFT_RESET 0xB6
#define ACC_CONF_100HZ 0xA8   /* 100 Hz, normal bandwidth, high-performance filter */
#define ACC_RANGE_4G 0x01
#define LSB_PER_G 8192.0f     /* ±4 g, 16-bit */
#define CHUNK 256
#define SAMPLE_US 20000
#define DOWN_G (-0.30f)
#define UP_G 0.22f
#define MIN_DOWN_MS 280
#define MAX_DOWN_MS 2200
#define MIN_REP_MS 600
#define SQUAT_GOAL 20
#define STEP_ON 0.028f        /* pocket walking peak of |a| minus gravity */
#define STEP_OFF 0.012f
#define STEP_LP 0.012f        /* ~1.6 s gravity so a stride is not tracked away */
#define STEP_BP 0.28f
#define STEP_MAX_THR 0.065f
#define MIN_STEP_MS 280
#define HIGH_MAX_MS 700
#define STEP_ARM_MS 400
#define IMU_MS 20
#define I2C_MS 20
#define RESYNC_MS 2000
#define RECOVER_MS 400

#include "boards/bmi270_config.inl"

typedef enum { RUN_OFF = 0, RUN_ON, RUN_PAUSE } run_t;

static i2c_master_dev_handle_t s_dev;
static bool s_ok;
static bool s_imu_on;
static volatile bool s_imu_run;
static TaskHandle_t s_imu_task;
static int s_i2c_miss;
static int64_t s_last_sample_us;
static int64_t s_recover_us;

static run_t s_squat_mode;
static bool s_squat_done;
static int s_count;
static float s_gx, s_gy, s_gz;
static float s_v;
static bool s_have_g;
static bool s_down;
static float s_bend;
static int64_t s_down_us;
static int64_t s_rep_us;
static int64_t s_active_us;
static int s_buzzed;

static run_t s_step_mode;
static volatile int s_steps;
static float s_mag_lp = 1.0f;
static float s_step_bp;
static float s_step_var = 0.02f;
static float s_step_peak;
static bool s_step_high;
static int64_t s_step_us;
static int64_t s_step_arm_us;
static int64_t s_high_us;
static enum { CAP_NONE = 0, CAP_SQUAT, CAP_STEPS } s_caption_src;

static esp_err_t accel_on(bool on);

static esp_err_t wr(uint8_t reg, uint8_t val)
{
    uint8_t buf[2] = { reg, val };
    return i2c_master_transmit(s_dev, buf, sizeof(buf), I2C_MS);
}

static esp_err_t rd(uint8_t reg, uint8_t *data, size_t n)
{
    return i2c_master_transmit_receive(s_dev, &reg, 1, data, n, I2C_MS);
}

static esp_err_t wr_n(uint8_t reg, const uint8_t *data, size_t n)
{
    uint8_t buf[1 + CHUNK];
    if (n > CHUNK) {
        return ESP_ERR_INVALID_SIZE;
    }
    buf[0] = reg;
    memcpy(buf + 1, data, n);
    return i2c_master_transmit(s_dev, buf, n + 1, 100);
}

static esp_err_t add_dev(i2c_master_bus_handle_t bus, uint8_t addr)
{
    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = addr,
        .scl_speed_hz = 400000,
    };
    return i2c_master_bus_add_device(bus, &cfg, &s_dev);
}

/* Re-enable the accelerometer without dropping the session. */
static bool imu_kick(void)
{
    int64_t now = esp_timer_get_time();
    if (s_recover_us && now - s_recover_us < (int64_t)RECOVER_MS * 1000) {
        return s_imu_on;
    }
    s_recover_us = now;
    if (accel_on(true) == ESP_OK) {
        s_imu_on = true;
        s_i2c_miss = 0;
        return true;
    }
    ESP_LOGW(TAG, "accelerometer retry failed");
    s_imu_on = false;
    return false;
}

static esp_err_t upload_config(void)
{
    ESP_RETURN_ON_ERROR(wr(REG_INIT_CTRL, 0x00), TAG, "init_ctrl off");
    for (size_t i = 0; i < sizeof(bmi270_config_file); i += CHUNK) {
        size_t n = sizeof(bmi270_config_file) - i;
        if (n > CHUNK) {
            n = CHUNK;
        }
        uint8_t addr[2] = { (uint8_t)((i >> 1) & 0x0F), (uint8_t)(i >> 5) };
        ESP_RETURN_ON_ERROR(wr_n(REG_INIT_ADDR_0, addr, 2), TAG, "init addr");
        ESP_RETURN_ON_ERROR(wr_n(REG_INIT_DATA, bmi270_config_file + i, n), TAG, "init data");
    }
    ESP_RETURN_ON_ERROR(wr(REG_INIT_CTRL, 0x01), TAG, "init_ctrl on");
    for (int i = 0; i < 40; i++) {
        uint8_t st = 0;
        if (rd(REG_INTERNAL_STATUS, &st, 1) == ESP_OK && (st & 0x01)) {
            return ESP_OK;
        }
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    ESP_LOGE(TAG, "BMI270 config did not start");
    return ESP_ERR_TIMEOUT;
}

static esp_err_t accel_on(bool on)
{
    if (on) {
        ESP_RETURN_ON_ERROR(wr(REG_PWR_CONF, 0x00), TAG, "pwr_conf");
        ESP_RETURN_ON_ERROR(wr(REG_PWR_CTRL, 0x04), TAG, "acc on");
        vTaskDelay(pdMS_TO_TICKS(5));
        ESP_RETURN_ON_ERROR(wr(REG_ACC_CONF, ACC_CONF_100HZ), TAG, "acc_conf");
        ESP_RETURN_ON_ERROR(wr(REG_ACC_RANGE, ACC_RANGE_4G), TAG, "acc_range");
    } else {
        wr(REG_PWR_CTRL, 0x00);
        wr(REG_PWR_CONF, 0x01);
    }
    return ESP_OK;
}

static bool read_g(float *ax, float *ay, float *az)
{
    uint8_t raw[6];
    if (rd(REG_ACC_X_LSB, raw, sizeof(raw)) != ESP_OK) {
        return false;
    }
    int16_t x = (int16_t)((uint16_t)raw[1] << 8 | raw[0]);
    int16_t y = (int16_t)((uint16_t)raw[3] << 8 | raw[2]);
    int16_t z = (int16_t)((uint16_t)raw[5] << 8 | raw[4]);
    *ax = x / LSB_PER_G;
    *ay = y / LSB_PER_G;
    *az = z / LSB_PER_G;
    return true;
}

static void show_status(void)
{
    if (muse_fit_active()) {
        return;
    }
    if (muse_hr_active()) {
        return;
    }
    if (muse_state_mode(NULL) != MUSE_MODE_IDLE) {
        return;
    }
    if (s_step_mode == RUN_ON) {
        muse_state_set_caption("STEPS %d", s_steps);
        return;
    }
    if (s_squat_done) {
        muse_state_set_caption("SQUATS %d/20\nCOMPLETE!!", s_count);
        return;
    }
    if (s_squat_mode == RUN_ON) {
        muse_state_set_caption("SQUATS %d/20\nKEEP GOING", s_count);
        return;
    }
    if (s_caption_src == CAP_STEPS && s_step_mode == RUN_PAUSE) {
        muse_state_set_caption("STEPS %d\nPAUSED", s_steps);
        return;
    }
    if (s_squat_mode == RUN_PAUSE) {
        muse_state_set_caption("SQUATS %d/20\nPAUSED", s_count);
        return;
    }
    if (s_step_mode == RUN_PAUSE) {
        muse_state_set_caption("STEPS %d\nPAUSED", s_steps);
        return;
    }
}

static void sync_imu(void)
{
    bool need = s_squat_mode == RUN_ON || s_step_mode == RUN_ON;
    if (need) {
        if (s_imu_run && s_imu_on) {
            return;
        }
        s_have_g = false;
        s_v = 0;
        s_down = false;
        s_down_us = s_rep_us = 0;
        s_mag_lp = 1.0f;
        s_step_bp = 0;
        s_step_var = 0.02f;
        s_step_high = false;
        s_step_peak = 0;
        s_i2c_miss = 0;
        s_last_sample_us = 0;
        s_imu_run = true;
        imu_kick();
        if (s_imu_task) {
            xTaskNotifyGive(s_imu_task);
        }
        return;
    }
    if (!s_imu_run && !s_imu_on) {
        return;
    }
    s_imu_run = false;
    s_bend = 0;
    accel_on(false);
    s_imu_on = false;
}

static void note_step(int64_t now)
{
    int since_ms = s_step_us ? (int)((now - s_step_us) / 1000) : MIN_STEP_MS;
    if (s_step_peak < STEP_ON || since_ms < MIN_STEP_MS) {
        return;
    }
    s_steps++;
    s_step_us = now;
    if (!muse_state_asleep()) {
        show_status();
    }
    if ((s_steps % 50) == 0) {
        ESP_LOGI(TAG, "step %d", s_steps);
    }
}

static void on_sample(void)
{
    if (s_squat_mode != RUN_ON && s_step_mode != RUN_ON) {
        return;
    }
    float ax, ay, az;
    if (!read_g(&ax, &ay, &az)) {
        if (++s_i2c_miss >= 5) {
            s_i2c_miss = 0;
            imu_kick();
            ESP_LOGW(TAG, "BMI270 recovered after missed samples");
        }
        return;
    }
    s_i2c_miss = 0;
    s_imu_on = true;
    int64_t now = esp_timer_get_time();
    if (s_last_sample_us && now - s_last_sample_us > (int64_t)RESYNC_MS * 1000) {
        /* A long gap would look like a huge step. Keep LP, drop the peak. */
        s_step_high = false;
        s_step_peak = 0;
    }
    s_last_sample_us = now;

    if (s_squat_mode == RUN_ON) {
        if (!s_have_g) {
            s_gx = ax;
            s_gy = ay;
            s_gz = az;
            s_have_g = true;
        } else {
            const float ag = 0.98f;
            s_gx = ag * s_gx + (1.0f - ag) * ax;
            s_gy = ag * s_gy + (1.0f - ag) * ay;
            s_gz = ag * s_gz + (1.0f - ag) * az;
            float g2 = s_gx * s_gx + s_gy * s_gy + s_gz * s_gz;
            if (g2 >= 0.25f) {
                float inv = 1.0f / sqrtf(g2);
                float vert = ax * s_gx * inv + ay * s_gy * inv + az * s_gz * inv - 1.0f;
                s_v = 0.65f * s_v + 0.35f * vert;
                if (!s_down && s_v < DOWN_G) {
                    s_down = true;
                    s_down_us = now;
                } else if (s_down) {
                    int ms = (int)((now - s_down_us) / 1000);
                    if (s_v > UP_G && ms >= MIN_DOWN_MS && ms <= MAX_DOWN_MS &&
                        (s_rep_us == 0 || now - s_rep_us > (int64_t)MIN_REP_MS * 1000)) {
                        s_count++;
                        s_rep_us = now;
                        s_down = false;
                        muse_fit_note_squat();
                        muse_state_poke();
                        ESP_LOGI(TAG, "squat %d", s_count);
                        if (s_count >= SQUAT_GOAL) {
                            s_squat_done = true;
                            s_squat_mode = RUN_PAUSE;
                            s_caption_src = CAP_SQUAT;
                            s_bend = 0;
                            sync_imu();
                            if (!muse_fit_active() && muse_state_mode(NULL) == MUSE_MODE_IDLE) {
                                muse_state_set_caption("SQUATS 20/20\nCOMPLETE!!");
                            }
                            muse_state_cheer();
                            muse_audio_fanfare_async();
                            ESP_LOGI(TAG, "squat goal reached");
                        } else {
                            show_status();
                        }
                    } else if (ms > MAX_DOWN_MS) {
                        s_down = false;
                    }
                }
            }
        }
        float target = s_down ? 1.0f : 0.0f;
        s_bend += (target - s_bend) * 0.18f;
        if (s_squat_mode == RUN_ON) {
            s_active_us += SAMPLE_US;
            int marks = (int)(s_active_us / (30LL * 1000000));
            if (marks > s_buzzed) {
                s_buzzed = marks;
                muse_audio_tick_async();
            }
        }
    } else {
        s_bend += (0.0f - s_bend) * 0.18f;
    }

    if (s_step_mode == RUN_ON && now >= s_step_arm_us) {
        float mag = sqrtf(ax * ax + ay * ay + az * az);
        /* Slow gravity so a pocket stride is not absorbed into the baseline. */
        s_mag_lp += (mag - s_mag_lp) * STEP_LP;
        float hp = mag - s_mag_lp;
        s_step_bp += (hp - s_step_bp) * STEP_BP;
        float d = s_step_bp;
        s_step_var += (d * d - s_step_var) * 0.008f;
        float rms = sqrtf(s_step_var < 0 ? 0 : s_step_var);
        float thr = STEP_ON + 0.12f * rms;
        if (thr > STEP_MAX_THR) {
            thr = STEP_MAX_THR;
        }
        if (!s_step_high && d > thr) {
            s_step_high = true;
            s_step_peak = d;
            s_high_us = now;
        } else if (s_step_high) {
            if (d > s_step_peak) {
                s_step_peak = d;
            }
            int high_ms = (int)((now - s_high_us) / 1000);
            if (d < s_step_peak * 0.45f && s_step_peak >= STEP_ON) {
                s_step_high = false;
                note_step(now);
                s_step_peak = 0;
            } else if (d < STEP_OFF || high_ms > HIGH_MAX_MS) {
                s_step_high = false;
                s_step_peak = 0;
            }
        }
    }

    static int idle_ticks;
    if (++idle_ticks >= 25) {
        idle_ticks = 0;
        if (s_step_mode == RUN_ON || s_squat_mode == RUN_ON) {
            if (!s_imu_on) {
                imu_kick();
            }
            if (s_last_sample_us && now - s_last_sample_us > (int64_t)400 * 1000) {
                imu_kick();
            }
        }
        if (s_squat_mode == RUN_ON) {
            if (!muse_state_asleep()) {
                show_status();
            }
            muse_state_poke();
        } else if (s_step_mode == RUN_ON && !muse_state_asleep()) {
            show_status();
        }
    }
}

static void imu_task(void *arg)
{
    (void)arg;
    int64_t next = esp_timer_get_time();
    for (;;) {
        if (!s_imu_run) {
            ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
            next = esp_timer_get_time();
            continue;
        }
        on_sample();
        if ((s_step_mode == RUN_ON || s_squat_mode == RUN_ON) && !s_imu_on) {
            imu_kick();
        }
        next += (int64_t)SAMPLE_US;
        int64_t now = esp_timer_get_time();
        int wait_ms = (int)((next - now) / 1000);
        if (wait_ms > IMU_MS) {
            wait_ms = IMU_MS;
            next = now + (int64_t)SAMPLE_US;
        }
        if (wait_ms > 0) {
            vTaskDelay(pdMS_TO_TICKS(wait_ms));
        } else {
            next = now;
            taskYIELD();
        }
    }
}

static esp_err_t init_bmi270(i2c_master_bus_handle_t bus)
{
    uint8_t addr = BMI270_ADDR;
    if (i2c_master_probe(bus, addr, 50) != ESP_OK) {
        addr = BMI270_ADDR_ALT;
        if (i2c_master_probe(bus, addr, 50) != ESP_OK) {
            ESP_LOGW(TAG, "no BMI270 on 0x69/0x68");
            return ESP_ERR_NOT_FOUND;
        }
    }
    ESP_RETURN_ON_ERROR(add_dev(bus, addr), TAG, "add BMI270");
    uint8_t id = 0;
    ESP_RETURN_ON_ERROR(rd(REG_CHIP_ID, &id, 1), TAG, "chip id");
    if (id != CHIP_ID) {
        ESP_LOGW(TAG, "unexpected IMU id 0x%02x", id);
        return ESP_ERR_NOT_FOUND;
    }
    ESP_RETURN_ON_ERROR(wr(REG_CMD, CMD_SOFT_RESET), TAG, "reset");
    vTaskDelay(pdMS_TO_TICKS(30));
    ESP_RETURN_ON_ERROR(wr(REG_PWR_CONF, 0x00), TAG, "disable power save");
    vTaskDelay(pdMS_TO_TICKS(1));
    ESP_RETURN_ON_ERROR(upload_config(), TAG, "config");
    ESP_RETURN_ON_ERROR(accel_on(false), TAG, "suspend");
    ESP_LOGI(TAG, "BMI270 ready at 0x%02x", addr);
    return ESP_OK;
}

esp_err_t muse_squat_init(i2c_master_bus_handle_t bus)
{
    esp_err_t err = init_bmi270(bus);
    if (err != ESP_OK) {
        return err;
    }
    if (xTaskCreatePinnedToCore(imu_task, "bmi270", 4096, NULL, MUSE_UI_PRIORITY + 2,
                                &s_imu_task, MUSE_UI_CORE ? 0 : 1) != pdPASS) {
        ESP_LOGE(TAG, "IMU task");
        return ESP_ERR_NO_MEM;
    }
    s_ok = true;
    return ESP_OK;
}

bool muse_squat_available(void)
{
    return s_ok;
}

static void squat_run(void)
{
    if (!s_ok) {
        return;
    }
    muse_timer_stop();
    if (s_step_mode == RUN_ON) {
        s_step_mode = RUN_PAUSE;
    }
    if (s_squat_done || s_squat_mode == RUN_OFF) {
        s_active_us = 0;
        s_buzzed = 0;
    }
    if (s_squat_done) {
        s_count = 0;
        s_squat_done = false;
    }
    s_squat_mode = RUN_ON;
    s_caption_src = CAP_SQUAT;
    s_have_g = false;
    s_down = false;
    sync_imu();
    muse_state_poke();
    show_status();
}

static void squat_pause(void)
{
    if (s_squat_mode != RUN_ON) {
        return;
    }
    s_squat_mode = RUN_PAUSE;
    s_caption_src = CAP_SQUAT;
    sync_imu();
    show_status();
}

void muse_squat_set_active(bool on)
{
    if (!s_ok) {
        return;
    }
    if (on) {
        squat_run();
    } else if (s_squat_mode == RUN_ON) {
        squat_pause();
    }
}

void muse_squat_toggle(void)
{
    if (s_squat_mode == RUN_ON) {
        squat_pause();
    } else {
        squat_run();
    }
}

void muse_squat_exit_reset(void)
{
    s_count = 0;
    s_squat_done = false;
    s_down = false;
    s_rep_us = 0;
    s_bend = 0;
    s_active_us = 0;
    s_buzzed = 0;
    s_squat_mode = RUN_OFF;
    if (s_caption_src == CAP_SQUAT) {
        s_caption_src = CAP_NONE;
    }
    sync_imu();
    if (muse_state_mode(NULL) == MUSE_MODE_IDLE) {
        if (s_step_mode == RUN_PAUSE) {
            s_caption_src = CAP_STEPS;
            show_status();
        } else {
            muse_state_set_caption("%s", "");
        }
    }
}

bool muse_squat_active(void)
{
    return s_squat_mode == RUN_ON;
}

bool muse_squat_paused(void)
{
    return s_squat_mode == RUN_PAUSE && !s_squat_done;
}

bool muse_squat_done(void)
{
    return s_squat_done;
}

int muse_squat_count(void)
{
    return s_count;
}

int muse_squat_goal(void)
{
    return SQUAT_GOAL;
}

void muse_squat_reset(void)
{
    s_count = 0;
    s_squat_done = false;
    s_down = false;
    s_rep_us = 0;
    show_status();
}

float muse_squat_bend(void)
{
    return s_squat_mode == RUN_ON ? s_bend : 0;
}

static void steps_run(void)
{
    if (!s_ok) {
        return;
    }
    muse_timer_stop();
    if (s_squat_mode == RUN_ON) {
        s_squat_mode = RUN_PAUSE;
    }
    s_step_mode = RUN_ON;
    s_caption_src = CAP_STEPS;
    s_step_high = false;
    s_step_peak = 0;
    s_step_bp = 0;
    s_high_us = 0;
    s_step_arm_us = esp_timer_get_time() + (int64_t)STEP_ARM_MS * 1000;
    sync_imu();
    muse_state_poke();
    show_status();
}

static void steps_pause(void)
{
    if (s_step_mode != RUN_ON) {
        return;
    }
    s_step_mode = RUN_PAUSE;
    s_caption_src = CAP_STEPS;
    sync_imu();
    show_status();
}

void muse_steps_set_active(bool on)
{
    if (!s_ok) {
        return;
    }
    if (on) {
        steps_run();
    } else if (s_step_mode == RUN_ON) {
        steps_pause();
    }
}

void muse_steps_toggle(void)
{
    if (s_step_mode == RUN_ON) {
        steps_pause();
    } else {
        steps_run();
    }
}

void muse_steps_exit_reset(void)
{
    int n = s_steps;
    s_steps = 0;
    s_step_high = false;
    s_step_mode = RUN_OFF;
    if (s_caption_src == CAP_STEPS) {
        s_caption_src = CAP_NONE;
    }
    sync_imu();
    if (n > 0) {
        muse_fit_note_steps(n);
        muse_fit_today_t t;
        muse_fit_today(&t);
        int pts = n / 10;
        muse_state_set_caption("STEPS +%d\n+%d  TODAY %d", n, pts, (int)t.steps);
        return;
    }
    if (muse_state_mode(NULL) == MUSE_MODE_IDLE) {
        if (s_squat_mode == RUN_PAUSE) {
            s_caption_src = CAP_SQUAT;
            show_status();
        } else {
            muse_state_set_caption("%s", "");
        }
    }
}

bool muse_steps_active(void)
{
    return s_step_mode == RUN_ON;
}

bool muse_steps_paused(void)
{
    return s_step_mode == RUN_PAUSE;
}

int muse_steps_count(void)
{
    return s_steps;
}
