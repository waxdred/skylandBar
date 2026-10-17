#ifndef SKYLAND_MACH_H
#define SKYLAND_MACH_H

#include <stdbool.h>
#include <stdint.h>

// Mach messages as the `sketchybar` CLI and SbarLua send them (compatibility): one out-of-line
// buffer per message, a reply port when the sender waits for an answer. They find the bar by the bootstrap
// name git.felix.<bar name>; helpers (SbarLua) get events on their own name.

/// A new port to receive on (with a send right), 0 on failure.
uint32_t skyland_mach_port(void);

/// Registers `port` under `name` in the bootstrap namespace. False when the name is taken
/// (SketchyBar runs) or registering fails.
bool skyland_mach_register(uint32_t port, const char *name);

/// Waits for a message on `port`. True with a malloc'ed copy of its buffer (NUL added after
/// `length` bytes, NULL when it had none) and the port to answer on (0: no answer wanted).
bool skyland_mach_receive(uint32_t port, char **data, uint32_t *length, uint32_t *reply);

/// Sends `length` bytes to `port`, without waiting for an answer; false when it failed
/// (gone, or full for 100 ms).
bool skyland_mach_send(uint32_t port, const char *data, uint32_t length);

/// The port registered under `name`, 0 when none.
uint32_t skyland_mach_look_up(const char *name);

/// Gives back a send right (a reply port once answered, a looked up port no longer used).
void skyland_mach_release(uint32_t port);

#endif
