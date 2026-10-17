#include "SkylandMach.h"

#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <stdlib.h>
#include <string.h>

struct message {
    mach_msg_header_t header;
    mach_msg_size_t descriptor_count;
    mach_msg_ool_descriptor_t descriptor;
};

struct buffer {
    struct message message;
    mach_msg_trailer_t trailer;
};

static mach_port_t bootstrap(void) {
    mach_port_t port = MACH_PORT_NULL;
    if (task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &port) != KERN_SUCCESS) return MACH_PORT_NULL;
    return port;
}

uint32_t skyland_mach_port(void) {
    mach_port_t task = mach_task_self(), port = MACH_PORT_NULL;
    if (mach_port_allocate(task, MACH_PORT_RIGHT_RECEIVE, &port) != KERN_SUCCESS) return 0;
    if (mach_port_insert_right(task, port, port, MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) return 0;
    return port;
}

bool skyland_mach_register(uint32_t port, const char *name) {
    mach_port_t bs = bootstrap(), existing = MACH_PORT_NULL;
    if (bs == MACH_PORT_NULL) return false;
    if (bootstrap_look_up(bs, name, &existing) == KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), existing);
        return false;
    }
    name_t service;
    strlcpy(service, name, sizeof(service));
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return bootstrap_register(bs, service, port) == KERN_SUCCESS;
#pragma clang diagnostic pop
}

bool skyland_mach_receive(uint32_t port, char **data, uint32_t *length, uint32_t *reply) {
    struct buffer buffer;
    memset(&buffer, 0, sizeof(buffer));
    *data = NULL;
    *length = 0;
    *reply = 0;
    kern_return_t result = mach_msg(&buffer.message.header, MACH_RCV_MSG, 0, sizeof(buffer), port,
                                    MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if (result != MACH_MSG_SUCCESS) return false;
    *reply = buffer.message.header.msgh_remote_port;
    if ((buffer.message.header.msgh_bits & MACH_MSGH_BITS_COMPLEX) && buffer.message.descriptor_count > 0
        && buffer.message.descriptor.address != NULL) {
        uint32_t size = buffer.message.descriptor.size;
        *data = malloc(size + 1);
        if (*data != NULL) {
            memcpy(*data, buffer.message.descriptor.address, size);
            (*data)[size] = 0;
            *length = size;
        }
        vm_deallocate(mach_task_self(), (vm_address_t)buffer.message.descriptor.address, size);
    }
    return true;
}

bool skyland_mach_send(uint32_t port, const char *data, uint32_t length) {
    struct message message;
    memset(&message, 0, sizeof(message));
    message.header.msgh_remote_port = port;
    message.header.msgh_local_port = MACH_PORT_NULL;
    message.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, MACH_MSGH_BITS_COMPLEX);
    message.header.msgh_size = sizeof(message);
    message.descriptor_count = 1;
    message.descriptor.address = (void *)data;
    message.descriptor.size = length;
    message.descriptor.copy = MACH_MSG_VIRTUAL_COPY;
    message.descriptor.deallocate = false;
    message.descriptor.type = MACH_MSG_OOL_DESCRIPTOR;
    return mach_msg(&message.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof(message), 0, MACH_PORT_NULL, 100,
                    MACH_PORT_NULL) == MACH_MSG_SUCCESS;
}

uint32_t skyland_mach_look_up(const char *name) {
    mach_port_t bs = bootstrap(), port = MACH_PORT_NULL;
    if (bs == MACH_PORT_NULL) return 0;
    if (bootstrap_look_up(bs, name, &port) != KERN_SUCCESS) return 0;
    return port;
}

void skyland_mach_release(uint32_t port) {
    if (port != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), port);
}
