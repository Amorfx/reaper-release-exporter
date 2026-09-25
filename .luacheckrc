std = "lua54"
read_globals = { "reaper" }
max_line_length = 140
exclude_files = { "Rendering/release_exporter/vendor/**", ".superpowers/**", "lua_modules/**", ".luarocks/**" }
files["tests/**"] = { std = "+busted" }
