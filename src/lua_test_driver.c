#include <stdio.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
    
int main (int argc, char* argv[]) {
	if (argc < 2) {
		fprintf(stderr, "Usage: %s <list of lua test files to run>", argv[0]);
	}
	
	int error;
	lua_State *L = luaL_newstate();   
	luaL_openlibs(L);
	
	int i = 1;
	while (i < argc) {
		error = luaL_loadfile(L, argv[i]);
		printf("\nRunning %s ...\n\n", argv[i]);
		i++;
		if (error) {
			fprintf(stderr, "Error while parsing file: %s", argv[i]);
			fprintf(stderr, "%s", lua_tostring(L, -1));
			lua_settop(L, 0);
			continue;
		}
		error = lua_pcall(L, 0, 0, 0);
		if (error) {
			fprintf(stderr, "Failed Tests: %s", argv[i]);
			fprintf(stderr, "%s", lua_tostring(L, -1));
			lua_settop(L, 0);
			continue;
		}
	}
	
	lua_getglobal(L, "printOverallSummary");
	lua_pcall(L, 0, 0, 0);

	lua_close(L);
	return 0;
}