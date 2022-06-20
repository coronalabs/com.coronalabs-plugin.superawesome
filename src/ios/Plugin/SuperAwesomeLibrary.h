//----------------------------------------------------------------------------
// SuperAwesomeLibrary.h
//
// Copyright (c) 2016 Corona Labs. All rights reserved.
//----------------------------------------------------------------------------

#ifndef _SuperAwesomeLibrary_H_
#define _SuperAwesomeLibrary_H_

#include "CoronaLua.h"
#include "CoronaMacros.h"

// This corresponds to the name of the library, e.g. [Lua] require "plugin.library"
// where the '.' is replaced with '_'
CORONA_EXPORT int luaopen_plugin_superawesome(lua_State *L);

#endif // _SuperAwesomeLibrary_H_
