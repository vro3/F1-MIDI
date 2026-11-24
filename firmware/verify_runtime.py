"""Run the linked workers against modeled hardware boundary calls, using their relative stacks."""
import sys
from pathlib import Path
sym={'await_ack': 86214, 'next': 86220}
import operator,struct,re
from functools import lru_cache
from capstone import Cs,CS_ARCH_XCORE
cpu=Cs(CS_ARCH_XCORE,0)
mem=bytearray(0x30000)
image=Path(sys.argv[1]).read_bytes()
rev=bytes(int(f'{x:08b}'[::-1],2) for x in range(256))
decoded=image.translate(rev)
tile=decoded[40:40+48468]
mem[65536:65536+len(tile)]=tile
@lru_cache(None)
def ins(pc):
    i=next(cpu.disasm(bytes(mem[pc:pc+4]),pc,count=1))
    return i.mnemonic,i.op_str.split(', '),pc+i.size
def wr(addr,val):struct.pack_into('<I',mem,addr,val&0xffffffff)
def rd(addr):return struct.unpack_from('<I',mem,addr)[0]
dp=0x1aee4
parent=0x25000-4*120
common=dict(dp=dp,cp=0x1aadc,lr=0x30000)
class VM:
    def __init__(self,pc,**values):
        self.r={**{f'r{i}':0 for i in range(12)},**common,**values};self.pc=pc
    def run(self,stop):
        r=self.r
        def val(s):return r[s] if s in r else int(s,0)
        def addr(s,w):
            a,b=re.fullmatch(r'(\w+)\[(\w+)\]',s).groups()
            return val(a)+w*val(b)
        for _ in range(30000):
            pc=self.pc
            if pc in stop:return pc
            op,a,self.pc=ins(pc);dest=a[0]
            if op=='bl':r['lr']=self.pc;self.pc+=val(dest)*2
            elif op=='bu':self.pc+=val(dest)*2
            elif op in ('bt','bf'):
                if bool(val(dest))==(op=='bt'):self.pc+=val(a[1])*2
            elif op in ('entsp','extsp'):
                if op=='entsp':wr(r['sp'],r['lr'])
                r['sp']-=4*val(dest)
            elif op=='retsp':
                if val(dest):
                    r['sp']+=4*val(dest);r['lr']=rd(r['sp'])
                self.pc=r['lr']
            elif op=='ldaw':r[dest]=addr(a[1],4)
            elif op in ('ldc','mov'):r[dest]=val(a[1])
            elif op=='ld8u':r[dest]=mem[addr(a[1],1)]
            elif op=='st8':mem[addr(a[1],1)]=r[dest]&255
            elif op=='ldw':r[dest]=rd(addr(a[1],4))
            elif op=='stw':wr(addr(a[1],4),r[dest])
            elif op in ('sext','zext'):
                w=val(a[1]);x=r[dest]&((1<<w)-1)
                r[dest]=(x-(1<<w) if op=='sext' and x>>(w-1) else x)&0xffffffff
            elif op=='mkmsk':r[dest]=(1<<val(a[1]))-1
            elif op in ('chkct','outct'):assert dest=='res[r8]'
            elif op=='out':
                assert r['r8']==77
                levels[r['r0']>>16]=r['r0']&65535
            else:
                ops={'add':operator.add,'sub':operator.sub,'and':operator.and_,'or':operator.or_,'xor':operator.xor,'shl':operator.lshift,'ashr':lambda x,y:((x^0x80000000)-0x80000000)>>y,'shr':operator.rshift,'eq':operator.eq,'lsu':operator.lt,'lss':lambda x,y:(x^0x80000000)<(y^0x80000000)}
                r[dest]=ops[op](val(a[1]),val(a[2]))&0xffffffff
        raise RuntimeError(hex(self.pc))
levels={}
VM(0x15038,sp=parent,r0=77).run({0x30000})
rx=VM(0x10554,sp=parent,r5=88)
def wake():
    v=VM(0x10fb4,sp=0x25f00);v.run({0x10fb8});return v.r['r1']
def tx():
    v=VM(0x10646,sp=parent-192*4,r6=0x21000,r7=99,r8=66)
    sent=[]
    while v.run({0x1064a,0x17188})!=0x1064a:
        assert v.r['r0']==99 and v.r['r3']==24
        a,n=v.r['r1'],v.r['r2'];sent.append(bytes(mem[a:a+n]))
        v.r['r0']=0;v.pc=v.r['lr']
    assert v.r['sp']==parent-192*4 and v.r['r8']==66
    return sent
def receive(data):
    assert rx.run({0x1715c})==0x1715c
    assert rx.r['r0']==88 and len(data)<=512
    a=rx.r['r1'];mem[a:a+len(data)]=data
    rx.r['r0']=len(data);rx.pc=rx.r['lr']
    out=[]
    while rx.run({0x1715c,sym['await_ack']})!=0x1715c:
        assert wake()
        out+=tx()
        assert rd(dp+151*4)==0
        rx.run({sym['next']})
    return out
assert wake() and tx()==[] and not wake()
def message(op,pad,rgb=(),tag=23):
    msg=bytes([240,125,70,49,1,tag,op,pad,*rgb,247])
    return b''.join(bytes([7 if i+3==len(msg) else 4])+msg[i:i+3] for i in range(0,len(msg),3))
for pad in range(16):
    color=(pad,60+pad,127-pad)
    req=message(2,pad,color); reply=message(3,pad,color)
    assert receive(req[:4])==[] and receive(req[4:])==[reply]
    assert receive(message(1,pad))==[reply]
    lut=decoded[0xad04+pad*3:0xad07+pad*3]
    for ch,v in zip(lut,(color[2],color[0],color[1])):assert levels[ch]==383-(v>>4)
    mem[0x21001+pad//8]=128>>(pad%8)
    assert tx()==[bytes([9,144,36+pad,127])]
    for ch,v in zip(lut,(color[2],color[0],color[1])):assert levels[ch]==383-2*v-(v>>1)
    mem[0x21001+pad//8]=0
    assert tx()==[bytes([8,128,36+pad,0])]
assert receive(message(2,16,(0,0,0)))==[]
assert receive(bytes(512-12)+message(1,3))==[message(3,3,(3,63,124))]
print("Packed XS1 image: 16 color writes, independent reads, RGB PWM, note presses/releases, 512-byte bulk and split transfers passed on modeled USB.")
for i in range(8):
    struct.pack_into('<H',mem,0x21006+2*i,3072)
    assert tx()==[bytes([11,176,16+i,96])]
for offset,n in [(3,6),(4,7)]:
    for i in range(n):
        mem[0x21000+offset]=128>>i
        note=36+(offset-1)*8+i
        assert tx()==[bytes([9,144,note,127])]
        mem[0x21000+offset]=0
        assert tx()==[bytes([8,128,note,0])]
mem[0x21005]=1
assert tx()==[bytes([11,176,24,1])]
mem[0x21005]=0
assert tx()==[bytes([11,176,24,127])]
print('Packed worker passed all 13 auxiliary buttons, eight analog CCs and both encoder directions.')
