#!/usr/bin/env python3
"""Smoke/integration tests for the AutoAudit PHP interface.

Uses only the Python standard library.  The runner records status, selected
assertions, and response metadata; credentials are never written to output.
"""
from http.cookiejar import CookieJar
from urllib.parse import urlencode
from urllib.request import Request, build_opener, HTTPCookieProcessor
from urllib.error import HTTPError, URLError
from html.parser import HTMLParser
import json, os, re, sys, time

BASE = os.environ.get("AUTOAUDIT_HTTP_BASE", "http://127.0.0.1:18087")
OUT = os.environ.get("AUTOAUDIT_HTTP_OUT", os.path.join(os.path.dirname(__file__), "resultados", "20261026_http"))
os.makedirs(OUT, exist_ok=True)

class FormParser(HTMLParser):
    def __init__(self): super().__init__(); self.token = None; self.forms = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "input" and a.get("name") == "token": self.token = a.get("value")
        if tag == "form": self.forms.append(a)

def get(opener, path):
    try:
        r = opener.open(Request(BASE + path, headers={"Accept":"text/html,text/csv"}), timeout=12)
        return r.status, r.headers, r.read()
    except HTTPError as e: return e.code, e.headers, e.read()

def post(opener, path, data):
    req = Request(BASE + path, data=urlencode(data, doseq=True).encode(), method="POST", headers={"Content-Type":"application/x-www-form-urlencoded"})
    try:
        r = opener.open(req, timeout=12); return r.status, r.headers, r.read()
    except HTTPError as e: return e.code, e.headers, e.read()

def check(results, name, ok, detail=""):
    results.append({"name":name, "ok":bool(ok), "detail":detail[:300]})

def login(user, password):
    jar = CookieJar(); op = build_opener(HTTPCookieProcessor(jar))
    status, _, body = get(op, "/login.php"); p = FormParser(); p.feed(body.decode("utf-8", "replace"))
    if not p.token: return op, False, "token ausente"
    status, headers, body = post(op, "/login.php", {"token":p.token, "usuario":user, "password":password})
    good = status == 302 or (status == 200 and b'Cerrar sesi' in body and b'name="usuario"' not in body)
    return op, good, f"HTTP {status}"

def main():
    results=[]; started=time.time()
    op=build_opener(HTTPCookieProcessor(CookieJar()))
    s,h,b=get(op,"/login.php"); check(results,"login_get_200",s==200 and b"Iniciar sesi" in b,f"HTTP {s}")
    p=FormParser(); p.feed(b.decode("utf-8","replace")); check(results,"login_csrf_present",bool(p.token))
    s,_,body=post(op,"/login.php",{"token":"invalid","usuario":"demo_maria","password":"Maria.2026"}); check(results,"csrf_rejected",s==200 and b'La sesi' in body and b'Cerrar sesi' not in body)
    op,bok,d=login("demo_maria","Maria.2026"); check(results,"maria_login",bok,d)
    if bok:
        for path, marker in [("/index.php",b"Panel"),("/configuracion.php",b"Configuraci"),("/consulta.php",b"Consulta")]:
            s,_,body=get(op,path); check(results,path+"_200",s==200 and marker in body,f"HTTP {s}")
        for q in ["?evento=BAD","?pagina=999999","?tabla[]=x","?csv=1"]:
            s,hh,body=get(op,"/consulta.php"+q); check(results,"consulta_invalid_"+q.replace("?",""),s in (200,400),f"HTTP {s} bytes {len(body)}")
        s,hh,body=get(op,"/consulta.php?csv=1&por_pagina=25"); check(results,"csv_content_type",s==200 and "text/csv" in hh.get("Content-Type","") and body.startswith(b"\xef\xbb\xbf"),f"HTTP {s}")
        s,_,body=get(op,"/logout.php"); check(results,"logout",s in (200,302))
    op,bok,d=login("demo_luis","Luis.2026"); check(results,"luis_login",bok,d)
    if bok:
        s,_,body=get(op,"/configuracion.php"); check(results,"luis_config_forbidden",s==403 and b"Acceso denegado" in body,f"HTTP {s}")
        s,_,body=get(op,"/consulta.php"); check(results,"luis_consulta",s==200 and b"Consulta" in body,f"HTTP {s}")
    op=build_opener(HTTPCookieProcessor(CookieJar())); s,_,body=get(op,"/login.php"); p=FormParser(); p.feed(body.decode("utf-8","replace")); s,_,body=post(op,"/login.php",{"token":p.token,"usuario":"demo_ana","password":"Ana.2026"}); check(results,"ana_blocked",b'no tiene acceso al sistema de auditor' in body and b'name="usuario"' in body,f"HTTP {s}")
    result={"base":BASE,"generated_at":time.strftime("%Y-%m-%dT%H:%M:%S%z"),"checks":results,"summary":{"total":len(results),"passed":sum(x["ok"] for x in results),"failed":sum(not x["ok"] for x in results),"duration_seconds":round(time.time()-started,2)}}
    with open(os.path.join(OUT,"resultados.json"),"w",encoding="utf-8") as f: json.dump(result,f,ensure_ascii=False,indent=2)
    print(json.dumps(result["summary"],ensure_ascii=False)); return 1 if result["summary"]["failed"] else 0

if __name__ == "__main__": sys.exit(main())
