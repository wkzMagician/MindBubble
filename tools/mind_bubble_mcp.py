"""Standard MCP server for MindBubble content operations.

Set MIND_BUBBLE_DB to the database used by the desktop/mobile app.
"""
import json, os, sqlite3, sys, time, uuid
from pathlib import Path

DB = Path(os.environ.get("MIND_BUBBLE_DB", Path.home() / "Documents" / "mind_bubble.db"))

def connect():
    db = sqlite3.connect(DB, timeout=10); db.row_factory = sqlite3.Row
    db.execute("PRAGMA busy_timeout = 10000")
    return db

def item(row):
    return {"id": row["id"], "title": row["title"], "description": row["description"], "appearanceFrequency": row["appearance_frequency"], "createdAt": row["created_at"], "updatedAt": row["updated_at"], "deletedAt": row["deleted_at"]}

def import_bubbles(args):
    rows, imported, skipped = args.get("items", []), [], []
    if not rows: raise ValueError("items must be a non-empty array")
    with connect() as db:
        for raw in rows:
            title, description = str(raw.get("title", "")).strip(), str(raw.get("description", "")).strip()
            if not title or not description: raise ValueError("title and description are required")
            if args.get("deduplicateByTitle", True) and db.execute("SELECT id FROM bubbles WHERE lower(title)=lower(?) AND deleted_at IS NULL", (title,)).fetchone(): skipped.append(title); continue
            now, ident = int(time.time()*1000), str(uuid.uuid4()); frequency = int(raw.get("appearanceFrequency", 3))
            if frequency not in range(1, 6): raise ValueError("appearanceFrequency must be 1..5")
            db.execute("INSERT INTO bubbles (id,title,description,created_at,updated_at,appearance_frequency,field_versions) VALUES (?,?,?,?,?,?,?)", (ident,title,description,now,now,frequency,"")); imported.append({"id": ident, "title": title})
    return {"imported": imported, "skipped": skipped}

def list_bubbles(args):
    with connect() as db: return {"bubbles": [item(row) for row in db.execute("SELECT * FROM bubbles WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT ?", (min(max(int(args.get("limit",100)),1),500),))]}
def search_bubbles(args):
    q = str(args.get("query", "")).strip()
    if not q: raise ValueError("query is required")
    with connect() as db: return {"bubbles": [item(row) for row in db.execute("SELECT * FROM bubbles WHERE deleted_at IS NULL AND (title LIKE ? OR description LIKE ?)", (f"%{q}%",f"%{q}%"))]}
def get_bubble(args):
    with connect() as db:
        row=db.execute("SELECT * FROM bubbles WHERE id=?",(args.get("id"),)).fetchone()
        if not row: raise ValueError("Bubble not found")
        return {"bubble": item(row)}
def update_bubble(args):
    ident=args.get("id"); allowed={"title":"title","description":"description","appearanceFrequency":"appearance_frequency"}; fields=[]; values=[]
    for key,col in allowed.items():
        if key in args: fields.append(col+"=?"); values.append(args[key])
    if not ident or not fields: raise ValueError("id and an editable field are required")
    values.extend([int(time.time()*1000),ident])
    with connect() as db: db.execute("UPDATE bubbles SET "+", ".join(fields)+", updated_at=? WHERE id=?",values)
    return get_bubble({"id":ident})
def delete_bubble(args):
    with connect() as db: db.execute("UPDATE bubbles SET deleted_at=?, updated_at=? WHERE id=?",(int(time.time()*1000),int(time.time()*1000),args.get("id")))
    return {"deleted": args.get("id")}

TOOLS=[{"name":name,"description":description,"inputSchema":{"type":"object","properties":{}}} for name,description in [("import_bubbles","Batch import concepts."),("list_bubbles","List non-deleted concepts."),("search_bubbles","Search concepts."),("get_bubble","Get one concept."),("update_bubble","Update a concept."),("delete_bubble","Delete a concept.")]]
HANDLERS={name:globals()[name] for name in ["import_bubbles","list_bubbles","search_bubbles","get_bubble","update_bubble","delete_bubble"]}
for line in sys.stdin:
 try:
  req=json.loads(line); method=req.get("method"); ident=req.get("id")
  if method=="initialize": result={"protocolVersion":req.get("params",{}).get("protocolVersion","2025-06-18"),"capabilities":{"tools":{}},"serverInfo":{"name":"mind-bubble","version":"1.0.0"}}
  elif method=="tools/list": result={"tools":TOOLS}
  elif method=="tools/call":
   data=HANDLERS[req["params"]["name"]](req["params"].get("arguments",{})); result={"content":[{"type":"text","text":json.dumps(data,ensure_ascii=False)}],"structuredContent":data,"isError":False}
  else: result={}
  print(json.dumps({"jsonrpc":"2.0","id":ident,"result":result},ensure_ascii=False),flush=True)
 except Exception as exc: print(json.dumps({"jsonrpc":"2.0","id":req.get("id"),"error":{"code":-32000,"message":str(exc)}},ensure_ascii=False),flush=True)
