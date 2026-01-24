Usage:
```
bazel build //server_nginx:docker_pkg
docker build -t webtiles-nginx-dev - < bazel-bin/server_nginx/docker_pkg.tar.gz
```
