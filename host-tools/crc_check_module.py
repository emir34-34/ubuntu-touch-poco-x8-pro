import struct,sys,glob,os
def elf(f):
    d=open(f,"rb").read()
    shoff,=struct.unpack_from("<Q",d,0x28); shnum,=struct.unpack_from("<H",d,0x3c); shstr,=struct.unpack_from("<H",d,0x3e)
    secs=[struct.unpack_from("<IIQQQQIIQQ",d,shoff+i*64) for i in range(shnum)]
    so=secs[shstr][4]
    nm=lambda o:d[so+o:d.index(b"\0",so+o)].decode()
    return d,secs,nm
def versions(f):
    d,secs,nm=elf(f); r={}
    for s in secs:
        if nm(s[0])=="__versions":
            for k in range(0,s[5],64):
                crc,=struct.unpack_from("<I",d,s[4]+k); r[d[s[4]+k+8:s[4]+k+64].split(b"\0")[0].decode()]=crc
    return r
def exports(f):
    d,secs,nm=elf(f); r={}
    st=[s for s in secs if s[1]==2][0]; strt=secs[st[6]]
    for k in range(0,st[5],24):
        a,info,o,sh,val,sz=struct.unpack_from("<IBBHQQ",d,st[4]+k)
        n=d[strt[4]+a:d.index(b"\0",strt[4]+a)].decode()
        if n.startswith("__crc_") and sh<len(secs):
            r[n[6:]]=struct.unpack_from("<I",d,secs[sh][4]+val)[0]
    return r
mod=sys.argv[1]; mdir=sys.argv[2]; symvers=sys.argv[3]
exp={}
for l in open(symvers):
    p=l.split("\t"); exp[p[1]]=(int(p[0],16),"vmlinux")
for f in glob.glob(mdir+"/*.ko"):
    for k,v in exports(f).items(): exp.setdefault(k,(v,os.path.basename(f)))
for k,v in versions(mod).items():
    e=exp.get(k)
    if e is None: print("MISSING",k)
    elif e[0]!=v: print("MISMATCH",k,hex(v),"vs",hex(e[0]),e[1])
print("checked",len(versions(mod)))
