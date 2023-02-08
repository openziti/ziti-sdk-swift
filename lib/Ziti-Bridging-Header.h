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

#include <ziti/ziti.h>
#include <ziti/ziti_src.h>
#include <ziti/ziti_model.h>
#include <tlsuv/http.h>
#include "ziti/ziti_tunnel.h"
#include "ziti/ziti_tunnel_cbs.h"
#include "ziti/netif_driver.h"
#include "ziti/model_support.h"
#include "ziti/ziti_dns.h"

extern const char** ziti_all_configs;
extern tls_context *default_tls_context(const char *ca, size_t ca_len);

void set_tunnel_logger(void);

typedef int (*ziti_printer_cb_wrapper)(void *ctx, const char *msg);
void ziti_dump_wrapper(ziti_context ztx, ziti_printer_cb_wrapper printer, void *ctx);

tunneled_service_t *ziti_sdk_c_on_service_wrapper(ziti_context ziti_ctx, ziti_service *service, int status, tunneler_context tnlr_ctx);

extern int ziti_log_level(const char *module, const char *file);
extern void ziti_log_set_level(int level, const char *marker);

char **copyStringArray(char *const arr[], int count);
void freeStringArray(char **arr);

char *copyString(const char *str);
void freeString(char *str);
