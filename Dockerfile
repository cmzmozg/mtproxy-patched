FROM python:3.11-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential libssl-dev libffi-dev && \
    pip install --no-cache-dir cryptography uvloop && \
    apt-get purge -y build-essential && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --system --no-create-home --shell /usr/sbin/nologin mtproxy

COPY mtproxy_patched.py /opt/mtproxy/mtproxy_patched.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/mtproxy/mtproxy_patched.py

EXPOSE 853 2443

ENTRYPOINT ["/entrypoint.sh"]
