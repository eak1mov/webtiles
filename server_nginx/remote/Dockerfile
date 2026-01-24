#FROM openresty/openresty:alpine
FROM openresty/openresty:jammy
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY handle_tiles.lua /usr/local/openresty/nginx/lua/handle_tiles.lua
