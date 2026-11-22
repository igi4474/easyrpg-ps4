// Tiny PS4 debug helpers: on-screen notification + klog line.
#pragma once
#include <string.h>
#include <stdio.h>
#include <orbis/libkernel.h>

static inline void ps4_klog(const char* msg) {
	char buf[1100];
	snprintf(buf, sizeof(buf), "<ERPG-DBG> %s\n", msg);
	sceKernelDebugOutText(0, buf);
}

static inline void ps4_notify(const char* msg) {
	ps4_klog(msg);
	OrbisNotificationRequest req;
	memset(&req, 0, sizeof(req));
	req.type = NotificationRequest;
	req.targetId = -1;
	strncpy(req.message, msg, sizeof(req.message) - 1);
	sceKernelSendNotificationRequest(0, &req, sizeof(req), 0);
}
