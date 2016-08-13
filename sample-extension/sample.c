#include <stdio.h>
#include <string.h>

#include "glirc-api.h"

static void *start(void) {
        FILE *file = fopen("sample-output.txt", "w");
        return file;
}

static void stop(void * S) {
        FILE *file = S;
        fclose(file);
}

static void process_message(void * S, struct glirc_message *msg) {
        FILE *file = S;
        char *cmd  = strndup(msg->command.str, msg->command.len);
        fprintf(file, "%s\n", cmd);
        fflush(file);
        free(cmd);
}

struct glirc_extension extension = {
        .start = start,
        .stop  = stop,
        .process_message = process_message
};
