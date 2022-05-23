/*
Copyright NetFoundry Inc.

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

typedef struct ziti_dump_ctx_s {
    void *ctx;
    ziti_printer_cb_wrapper printer;
} ziti_dump_ctx;

ZITI_FUNC extern void
ziti_logger(int level, const char *module, const char *file, unsigned int line, const char *func,
            const char *fmt, ...);

void set_tunnel_logger(void) {
    ziti_tunnel_set_logger(ziti_logger);
}

int ziti_dump_printer(void *ctx, const char *fmt, ...) {
    ziti_dump_ctx *zdctx = ctx;
    static char msg[4096];
    
    va_list vargs;
    va_start(vargs, fmt);
    vsnprintf(msg, sizeof(msg), fmt, vargs);
    va_end(vargs);
    
    return zdctx->printer(zdctx->ctx, msg);
}

void ziti_dump_wrapper(ziti_context ztx, ziti_printer_cb_wrapper printer, void *ctx) {
    ziti_dump_ctx zdctx;
    zdctx.ctx = ctx;
    zdctx.printer = printer;
    ziti_dump(ztx, ziti_dump_printer, &zdctx);
}

tunneled_service_t *ziti_sdk_c_on_service_wrapper(ziti_context ziti_ctx, ziti_service *service, int status, tunneler_context tnlr_ctx) {
    return ziti_sdk_c_on_service(ziti_ctx, service, status, tnlr_ctx);
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
