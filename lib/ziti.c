/*
Copyright 2020 NetFoundry, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ziti/ziti_tunnel_cbs.h"
#include "Ziti-Bridging-Header.h"

static const char* _ziti_all[] = {
   "all", NULL
};

const char** ziti_all_configs = _ziti_all;

void ziti_sdk_c_host_v1_wrapper(void *ziti_ctx, uv_loop_t *loop, const char *service_id, const char *proto, const char *hostname, int port) {
    ziti_sdk_c_host_v1(ziti_ctx, loop, service_id, proto, hostname, port);
}

static bytes_consumed_cb_context *bc_context = NULL;
void set_bytes_consumed_cb(bytes_consumed_cb_context *bcc) {
    bc_context = bcc;
}
static void my_on_ziti_write(ziti_connection ziti_conn, ssize_t len, void *ctx) {
    printf("wrote %zd bytes\n", len);
    if (bc_context != NULL) {
        bc_context->cb(len, bc_context->user_data);
    }
    ziti_tunneler_ack(ctx);
}
ssize_t ziti_sdk_c_write_wrapper(const void *ziti_io_ctx, void *write_ctx, const void *data, size_t len) {
    struct ziti_io_ctx_s *_ziti_io_ctx = (struct ziti_io_ctx_s *)ziti_io_ctx;
    return ziti_write(_ziti_io_ctx->ziti_conn, (void *)data, len, my_on_ziti_write, write_ctx);
}

char **copyStringArray(char *const arr[], int count) {
    if (count == 0) return 0;
        
    size_t sz = sizeof(char*);
    char **arrCpy = calloc((count + 1), sz);
    memcpy(arrCpy, arr, count * sz);
    return arrCpy;
}

void freeStringArray(char **arr) {
    if (arr) free(arr);
}

char *copyString(const char *str) {
    return str ? strdup(str) : NULL;
}

void freeString(char *str) {
    if (str) free(str);
}
