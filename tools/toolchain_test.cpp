// Toolchain smoke test for PS4: C++ runtime, SDL2 video (software renderer like EasyRPG), DualShock input.
#include <string>
#include <vector>
#include <memory>
#include <stdexcept>
#include <SDL.h>
#include <orbis/SystemService.h>
#include "ps4_notify.h"

static char msgbuf[512];

int main(int argc, char* argv[]) {
	ps4_notify("TEST 1/5: main() reached");

	std::vector<std::string> v{"C++", " runtime"};
	auto p = std::make_unique<std::string>(v[0] + v[1]);
	bool caught = false;
	try { throw std::runtime_error("x"); } catch (const std::exception&) { caught = true; }
	snprintf(msgbuf, sizeof(msgbuf), "TEST 2/5: %s OK (exceptions %s)", p->c_str(), caught ? "OK" : "BROKEN");
	ps4_notify(msgbuf);

	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMECONTROLLER) != 0) {
		snprintf(msgbuf, sizeof(msgbuf), "TEST 3/5: SDL_Init FAILED: %s", SDL_GetError());
		ps4_notify(msgbuf);
		SDL_Delay(4000);
		sceSystemServiceLoadExec("EXIT", NULL);
		return 1;
	}
	ps4_notify("TEST 3/5: SDL_Init OK");

	SDL_Window* win = SDL_CreateWindow("test", 0, 0, 1920, 1080, SDL_WINDOW_FULLSCREEN);
	SDL_Renderer* ren = win ? SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE) : nullptr;
	if (!ren) {
		snprintf(msgbuf, sizeof(msgbuf), "TEST 4/5: window/renderer FAILED: %s", SDL_GetError());
		ps4_notify(msgbuf);
		SDL_Delay(4000);
		sceSystemServiceLoadExec("EXIT", NULL);
		return 1;
	}
	ps4_notify("TEST 4/5: window OK - screen should turn GREEN. Press X to finish.");

	SDL_GameController* pad = nullptr;
	bool done = false;
	Uint32 start = SDL_GetTicks();
	while (!done && SDL_GetTicks() - start < 20000) {
		SDL_Event e;
		while (SDL_PollEvent(&e)) {
			if (e.type == SDL_CONTROLLERDEVICEADDED && !pad) {
				pad = SDL_GameControllerOpen(e.cdevice.which);
				ps4_notify(pad ? "TEST: controller detected" : "TEST: controller open FAILED");
			}
			if (e.type == SDL_CONTROLLERBUTTONDOWN && e.cbutton.button == SDL_CONTROLLER_BUTTON_A) {
				done = true;
			}
		}
		SDL_SetRenderDrawColor(ren, 0, 160, 0, 255);
		SDL_RenderClear(ren);
		SDL_RenderPresent(ren);
		SDL_Delay(16);
	}
	ps4_notify(done ? "TEST 5/5: X pressed - ALL OK" : "TEST 5/5: timeout (no X press seen)");
	SDL_Delay(1500);
	SDL_Quit();
	sceSystemServiceLoadExec("EXIT", NULL);
	return 0;
}
