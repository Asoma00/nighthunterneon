"""Скачивает из официального архива шаблонов Godot 4.7.2 только нужные файлы
(например ios.zip или web_nothreads_release.zip), не загружая весь архив (~1 ГБ).

Использование: python3 tools/get_templates.py <папка_шаблонов> <файл> [<файл> ...]
"""
import io
import os
import sys
import urllib.request
import zipfile

URL = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"


class HttpFile(io.RawIOBase):
    """Файл по HTTP с чтением кусками (Range): zipfile читает только нужные части."""

    def __init__(self, url):
        r = urllib.request.urlopen(urllib.request.Request(url, method="HEAD"))
        self.size = int(r.headers["Content-Length"])
        self.url = r.url
        self.pos = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def readinto(self, b):
        n = len(b)
        if n == 0 or self.pos >= self.size:
            return 0
        end = min(self.size, self.pos + n) - 1
        req = urllib.request.Request(self.url, headers={"Range": "bytes=%d-%d" % (self.pos, end)})
        d = urllib.request.urlopen(req).read()
        b[: len(d)] = d
        self.pos += len(d)
        return len(d)


def main():
    dest = sys.argv[1]
    os.makedirs(dest, exist_ok=True)
    z = zipfile.ZipFile(io.BufferedReader(HttpFile(URL), buffer_size=1 << 20))
    for name in sys.argv[2:] + ["version.txt"]:
        with z.open("templates/" + name) as src, open(os.path.join(dest, name), "wb") as out:
            while True:
                chunk = src.read(1 << 22)
                if not chunk:
                    break
                out.write(chunk)
        print("готово:", name)


if __name__ == "__main__":
    main()
