"""Author the original Tycoon Hub low-poly GLB asset kit. Standard-library only."""
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'client/assets/models'
TAU = math.tau


def color(hex_value):
    return [int(hex_value[i:i+2], 16) / 255 for i in (0, 2, 4)]


def transform(v, pos, rot):
    x, y, z = v
    for axis, angle in enumerate(rot):
        c, s = math.cos(angle), math.sin(angle)
        if axis == 0: y, z = y*c-z*s, y*s+z*c
        elif axis == 1: x, z = x*c+z*s, -x*s+z*c
        else: x, y = x*c-y*s, x*s+y*c
    return [x+pos[0], y+pos[1], z+pos[2]]


def lathe(profile, sides=16):
    verts = [(r*math.cos(i*TAU/sides), y, r*math.sin(i*TAU/sides)) for y, r in profile for i in range(sides)]
    faces = []
    for row in range(len(profile)-1):
        for i in range(sides):
            a = row*sides+i; b=row*sides+(i+1)%sides
            faces.append([a, a+sides, b+sides, b])
    faces += [list(reversed(range(sides))), list(range((len(profile)-1)*sides, len(profile)*sides))]
    return verts, faces


def rounded_box(size, bevel=.04):
    x,y,z = (v/2 for v in size)
    b=min(bevel, x*.4, y*.4, z*.4)
    verts=[]
    for height, inset in [(-y,b),(-y+b,0),(y-b,0),(y,b)]:
        a,c=x-inset,z-inset
        cut=min(b, a*.3,c*.3)
        verts += [(a-cut,height,-c),(-a+cut,height,-c),(-a,height,-c+cut),(-a,height,c-cut),(-a+cut,height,c),(a-cut,height,c),(a,height,c-cut),(a,height,-c+cut)]
    faces=[list(reversed(range(8))),list(range(24,32))]
    for row in range(3):
        for i in range(8):faces.append([row*8+i,row*8+(i+1)%8,(row+1)*8+(i+1)%8,(row+1)*8+i])
    return verts,faces


def sphere(radius, scale=(1,1,1), sides=16, rings=8):
    verts,faces=lathe([(-radius*math.cos(j*math.pi/rings),max(.0001,radius*math.sin(j*math.pi/rings))) for j in range(rings+1)],sides)
    return [(x*scale[0],y*scale[1],z*scale[2]) for x,y,z in verts],faces


def torus(radius=.24, tube=.065, segments=20, rings=8, wave=0):
    verts=[];faces=[]
    for i in range(segments):
        a=i*TAU/segments
        for j in range(rings):
            b=j*TAU/rings
            r=radius+tube*math.cos(b)
            verts.append((r*math.cos(a),tube*math.sin(b)+wave*math.sin(a*5),r*math.sin(a)))
    for i in range(segments):
        for j in range(rings): faces.append([i*rings+j,((i+1)%segments)*rings+j,((i+1)%segments)*rings+(j+1)%rings,i*rings+(j+1)%rings])
    return verts,faces


class Model:
    def __init__(self,name):
        self.name=name
        self.nodes=[{'name':name,'children':[]}]
        self.groups=defaultdict(lambda:[[],[],[]])
        self.triangles=0
    def node(self,name,pos=(0,0,0),rotation=None,parent=0):
        d={'name':name,'translation':list(pos),'children':[]}
        if rotation is not None:d['rotation']=rotation
        self.nodes.append(d);index=len(self.nodes)-1;self.nodes[parent]['children'].append(index)
        return index
    def geometry(self, geometry, pos, tint, rot=(0,0,0), parent=0, material='Solid'):
        verts,faces=geometry
        points=[transform(v,pos,rot) for v in verts]
        rgb=color(tint)
        group=self.groups[(parent,material)]
        for face in faces:
            for i in range(1,len(face)-1):
                tri=[points[face[j]] for j in (0,i,i+1)]
                a=[tri[1][k]-tri[0][k] for k in range(3)];b=[tri[2][k]-tri[0][k] for k in range(3)]
                n=[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
                length=math.sqrt(sum(v*v for v in n))
                if length<1e-10:continue
                normal=[v/length for v in n]
                group[0].extend(tri);group[1].extend([normal]*3);group[2].extend([rgb]*3)
                self.triangles+=1
    def box(self,pos,size,tint,bevel=.04,rot=(0,0,0),parent=0,material='Solid'):
        self.geometry(rounded_box(size,bevel),pos,tint,rot,parent,material)
    def lathe(self,pos,profile,tint,sides=16,rot=(0,0,0),parent=0,material='Solid'):
        self.geometry(lathe(profile,sides),pos,tint,rot,parent,material)
    def ball(self,pos,radius,tint,scale=(1,1,1),parent=0,material='Solid'):
        self.geometry(sphere(radius,scale),pos,tint,parent=parent,material=material)
    def ring(self,pos,radius,tube,tint,rot=(0,0,0),parent=0,wave=0):
        self.geometry(torus(radius,tube,wave=wave),pos,tint,rot,parent)
    def pipe(self,a,b,r,tint,parent=0):
        delta=[b[k]-a[k] for k in range(3)];length=math.sqrt(sum(v*v for v in delta))
        # Local cylinder points up Y, then tilt towards the target.
        self.lathe(tuple((a[k]+b[k])/2 for k in range(3)),[(-length/2,r),(length/2,r)],tint,12,rot=(math.atan2(delta[2],delta[1]),0,-math.atan2(delta[0],math.hypot(delta[1],delta[2]))),parent=parent)
    def leaf(self,pos,scale,tint,rot=(0,0,0),parent=0):
        v=[(0,0,0),(-.22,.2,.07),(0,.55,.04),(.22,.2,.07),(0,.2,-.08)]
        self.geometry(([(x*scale,y*scale,z*scale) for x,y,z in v],[[0,1,2],[0,2,3],[0,4,1],[0,3,4],[1,4,2],[2,4,3]]),pos,tint,rot,parent)
    def save(self):
        blob=bytearray();views=[];accessors=[];meshes=[]
        material_defs=[('Solid',0,.8,1),('Metal',.65,.35,1),('Glass',0,.12,.19),('Shirt',0,.8,1)]
        materials=[]
        for name,metal,rough,alpha in material_defs:
            base=[1,1,1,alpha]
            if name=='Shirt':base=color('62bbc0')+[1]
            material={'name':name,'pbrMetallicRoughness':{'baseColorFactor':base,'metallicFactor':metal,'roughnessFactor':rough},'doubleSided':True}
            if alpha<1:material.update(alphaMode='BLEND')
            materials.append(material)
        def accessor(values):
            while len(blob)%4:blob.append(0)
            offset=len(blob);flat=[v for vector in values for v in vector]
            blob.extend(struct.pack('<'+'f'*len(flat),*flat))
            views.append({'buffer':0,'byteOffset':offset,'byteLength':len(flat)*4,'target':34962})
            accessors.append({'bufferView':len(views)-1,'componentType':5126,'count':len(values),'type':'VEC3','min':[min(v[k] for v in values) for k in range(3)],'max':[max(v[k] for v in values) for k in range(3)]})
            return len(accessors)-1
        parents=defaultdict(list)
        for (parent,material),(positions,normals,colors) in self.groups.items():
            parents[parent].append({'attributes':{'POSITION':accessor(positions),'NORMAL':accessor(normals),'COLOR_0':accessor(colors)},'material':[m[0] for m in material_defs].index(material),'mode':4})
        for parent,primitives in parents.items():
            self.nodes[parent]['mesh']=len(meshes);meshes.append({'name':self.nodes[parent]['name'],'primitives':primitives})
        document={'asset':{'version':'2.0','generator':'Tycoon Hub original model authoring kit'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':self.nodes,'meshes':meshes,'materials':materials,'buffers':[{'byteLength':len(blob)}],'bufferViews':views,'accessors':accessors}
        raw=json.dumps(document,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);blob+=b'\0'*((-len(blob))%4)
        data=struct.pack('<III',0x46546c67,2,12+8+len(raw)+8+len(blob))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(blob),0x004e4942)+blob
        OUT.mkdir(parents=True,exist_ok=True);(OUT/(self.name+'.glb')).write_bytes(data)
        return {'file':self.name+'.glb','triangles':self.triangles,'bytes':len(data),'mesh_primitives':len(self.groups)}


WOOD='ac7749'; LIGHTWOOD='d4aa72'; STEEL='b9cbd2'; DARK='344b58'; CREAM='fff2d8'; GREEN='69ad65'; PINK='e88fa9'

def feet(m,width=1.8,depth=.9):
    for x in [-width/2,width/2]:
        for z in [-depth/2,depth/2]:m.box((x,.2,z),(.1,.4,.1),DARK,.02)

def register(m,pos=(.8,1.35,.05)):
    x,y,z=pos
    m.box((x,y,z),(.42,.22,.4),DARK)
    m.box((x,y+.2,z-.1),(.4,.3,.08),DARK,rot=(-.2,0,0))
    m.box((x,y+.2,z-.15),(.3,.19,.01),'8dd7b9',.005,rot=(-.2,0,0))
    for n in range(4):m.box((x-.1+n*.065,y+.13,z+.14),(.045,.025,.045),'e7ddc4',.008)

def crate(m,pos=(0,.3,0),width=1.9,depth=1):
    x,y,z=pos
    m.box((x,y-.22,z),(width,.08,depth),WOOD)
    for side in [-1,1]:
        for row in range(3):m.box((x,y-.1+row*.14,z+side*depth/2),(width,.1,.055),LIGHTWOOD,.012)
        for row in range(3):m.box((x+side*width/2,y-.1+row*.14,z),(.055,.1,depth),LIGHTWOOD,.012)
    for dx in [-width/2,width/2]:
        for dz in [-depth/2,depth/2]:m.box((x+dx,y+.05,z+dz),(.08,.65,.08),WOOD,.015)

def planter(m,pos):
    x,y,z=pos
    m.lathe((x,y,z),[(0,.18),(.06,.19),(.34,.26),(.39,.28),(.42,.28)],'c98260')
    for i in range(5):m.leaf((x,y+.38,z),.8,GREEN,(0,i*TAU/5,.3))

def chair(m,x,z,turn=0):
    m.box((x,.48,z),(.65,.16,.65),PINK,.07)
    m.box((x,.87,z+.26),(.65,.72,.14),PINK,.07)
    for dx in [-.23,.23]:
        for dz in [-.23,.23]:m.pipe((x+dx,.42,z+dz),(x+dx*1.25,.02,z+dz*1.25),.035,DARK)

def table(m):
    m.lathe((0,.81,0),[(-.07,.68),(0,.76),(.08,.73)],LIGHTWOOD,24)
    m.lathe((0,.4,0),[(-.38,.22),(-.31,.26),(-.26,.09),(.35,.09)],DARK)
    for x in [-1.1,1.1]:chair(m,x,0)
    planter(m,(0,.91,0))

def character():
    m=Model('character')
    m.lathe((0,.78,0),[(-.28,.23),(-.23,.3),(.19,.3),(.26,.23)],'ffffff',16,material='Shirt')
    m.box((0,.65,-.245),(.37,.44,.045),'f0eee0',.025)
    m.box((0,.78,-.285),(.22,.13,.025),'d6cba9',.015)
    for x in [-.13,.13]:m.pipe((x,.97,-.24),(x,.61,-.25),.025,'e1d6bf')
    m.ball((0,1.26,0),.3,'f3c59e',scale=(1,.98,.94))
    m.ball((0,1.44,.065),.29,'634635',scale=(1,.48,.92))
    for x in [-.105,.105]:
        m.ball((x,1.28,-.265),.046,'ffffff',scale=(1,1,.4))
        m.ball((x,1.28,-.284),.027,'253743',scale=(1,1,.5))
    m.ball((0,1.2,-.282),.042,'e6ae8d',scale=(.8,.65,1))
    m.box((0,1.135,-.265),(.11,.025,.015),'9b654e',.007)
    hat=m.node('ChefHat')
    m.lathe((0,1.51,0),[(-.035,.29),(.065,.29),(.12,.24)],CREAM,parent=hat)
    for x,z in [(0,0),(-.14,0),(.14,0),(0,-.12),(0,.12)]:m.ball((x,1.73,z),.18,CREAM,scale=(1,.9,1),parent=hat)
    cap=m.node('Cap')
    m.ball((0,1.49,.03),.29,'ffffff',scale=(1,.35,.95),parent=cap,material='Shirt')
    m.box((0,1.45,-.26),(.4,.045,.24),'ffffff',.02,parent=cap,material='Shirt')
    for side,x in [('Left',-.145),('Right',.145)]:
        leg=m.node(side,(x,.5,0))
        m.lathe((0,-.18,0),[(-.18,.1),(-.13,.12),(.14,.115),(.19,.1)],'35455c',parent=leg)
        m.box((0,-.43,-.055),(.24,.15,.36),'273849',.04,parent=leg)
        arm=m.node(side+'Arm',(x*2.4,.94,0))
        m.lathe((0,-.14,0),[(-.15,.09),(.08,.11),(.12,.085)],'ffffff',parent=arm,material='Shirt')
        m.ball((0,-.34,-.04),.105,'f3c59e',parent=arm)
    return m


def item_model(name):
    m=Model(name)
    if name in ('donut','chocolate_donut'):
        m.ring((0,.09,0),.17,.08,'d3a361')
        tint=PINK if name=='donut' else '704535'
        m.ring((0,.14,0),.17,.061,tint,wave=.009)
        for i in range(13):
            a=i*TAU/13;r=.16+(i%3-1)*.025
            m.box((math.cos(a)*r,.2,math.sin(a)*r),(.045,.014,.018),['fff0b1','ffffff','7bc9bf'][i%3],.006,rot=(0,a*.7,0))
    elif name in ('tomato','apple'):
        tint='dd524b' if name=='tomato' else 'd95646'
        m.ball((0,.12,0),.2,tint,scale=(1,.85,1))
        m.pipe((0,.25,0),(.015,.33,0),.025,'775633')
        for i in range(3):m.leaf((0,.27,0),.25,GREEN,(.9,i*TAU/3,0))
    elif name=='coffee':
        m.lathe((0,0,0),[(0,.13),(.035,.14),(.24,.18),(.27,.18)],CREAM)
        m.lathe((0,.12,0),[(0,.154),(.08,.17)],'b98a68')
        m.lathe((0,.28,0),[(-.02,.185),(.015,.185),(.04,.16)],'f5f0e5')
        m.box((0,.13,-.155),(.12,.08,.015),'697f69',.015)
    elif name=='juice':
        m.lathe((0,0,0),[(0,.13),(.05,.15),(.3,.15),(.35,.07),(.42,.065)],'e7a354')
        m.lathe((0,.41,0),[(0,.075),(.07,.075)],'f6f1dc')
        m.box((0,.2,-.14),(.17,.14,.025),'fff0cc',.015)
        m.ball((0,.2,-.161),.05,'d7863d',scale=(1,1,.18))
    elif name in ('beans','dough'):
        tint='c59a6b' if name=='beans' else 'ead4a2'
        m.lathe((0,0,0),[(0,.1),(.04,.19),(.19,.2),(.29,.16),(.34,.09)],tint,12)
        m.box((0,.35,0),(.17,.04,.07),'e9c288',.012)
        m.box((0,.18,-.185),(.21,.16,.02),'fff0d4',.016)
        m.ball((0,.18,-.205),.055,'7a5338' if name=='beans' else 'b28e4d',scale=(.8,1,.15))
    elif name=='scrap':
        m.ring((0,.07,0),.145,.04,'738b95')
        m.box((.05,.14,0),(.3,.06,.14),'a7724f',rot=(.2,.4,.2))
        m.pipe((-.13,.06,-.1),(.11,.2,.08),.04,STEEL)
    elif name=='parts':
        m.lathe((0,0,0),[(0,.18),(.06,.18),(.08,.1),(.17,.1)],STEEL,12)
        for i in range(8):m.box((math.cos(i*TAU/8)*.18,.035,math.sin(i*TAU/8)*.18),(.08,.08,.1),STEEL,.012,rot=(0,-i*TAU/8,0))
        m.lathe((0,.18,0),[(0,.045),(.03,.045)],DARK)
    else:
        m.box((0,.025,0),(.32,.06,.18),'588c4c',.012)
        m.box((0,.059,0),(.1,.012,.19),'e7e6bd',.005)
        m.ball((-.07,.06,0),.047,'a6ce7c',scale=(1,.1,1))
    return m


def station_model(name):
    m=Model(name)
    if name=='tomato_plot':
        m.box((0,.12,0),(2.4,.25,1.45),'785036',.07)
        for x in [-1.23,1.23]:m.box((x,.17,0),(.13,.3,1.6),LIGHTWOOD,.025)
        for z in [-.75,.75]:m.box((0,.17,z),(2.5,.3,.1),LIGHTWOOD,.025)
        for x in [-.8,0,.8]:
            m.pipe((x,.2,0),(x,.92,0),.035,'487e42')
            m.pipe((x,.2,-.22),(x,1.15,-.22),.025,WOOD)
            for i in range(4):m.leaf((x,.32+i*.15,0),.65,['55984e','6ab65a'][i%2],(.3,i*1.8,.4))
        m.node('StockAnchor',(0,.75,.26))
    elif name=='orchard_tree':
        m.box((0,.08,0),(2.4,.16,1.45),'8ca765',.07)
        for x in [-.6,.6]:
            m.lathe((x,0,0),[(0,.17),(.14,.14),(1.3,.075),(1.6,.04)],'906343',10)
            for direction in [-1,1]:m.pipe((x,.7,0),(x+direction*.32,1.4,.05),.05,'906343')
            for dx,y,dz,r in [(-.28,1.55,0,.4),(.25,1.65,.08,.42),(0,1.9,-.05,.45),(0,1.5,.23,.4)]:m.ball((x+dx,y,dz),r,['659d48','76ad51'][int(y*10)%2])
        m.node('StockAnchor',(0,1.38,.4))
    elif name in ('ingredient_pallet','coffee_delivery'):
        for x in [-.75,0,.75]:m.box((x,.1,0),(.13,.2,1.25),WOOD)
        for z in [-.5,-.25,0,.25,.5]:m.box((0,.22,z),(2.1,.08,.21),LIGHTWOOD,.015)
        for x in [-.87,.87]:m.box((x,.65,-.45),(.1,1.05,.1),WOOD)
        m.box((0,1.2,-.45),(1.95,.2,.11),LIGHTWOOD)
        m.node('StockAnchor',(0,.5,0))
    elif name=='scrap_bin':
        m.box((0,.23,0),(2.15,.42,1.2),'687f85',.08)
        for x in [-1.0,1.0]:m.box((x,.6,0),(.1,.8,1.3),'536b74',.025)
        m.box((0,.7,-.58),(2,.9,.1),'536b74')
        for i in range(4):m.box((-.78+i*.5,.24,.61),(.22,.19,.03),'eab95d',.006,rot=(0,0,-.2))
        m.node('StockAnchor',(0,.62,.05))
    elif name in ('donut_fryer','chocolate_glazer','coffee_roaster','juice_press','recycler'):
        feet(m)
        accent={'donut_fryer':PINK,'chocolate_glazer':'936454','coffee_roaster':'738d86','juice_press':'8bb77e','recycler':'e0aa46'}[name]
        m.box((0,.68,0),(1.92,.95,1.15),accent,.12)
        m.box((0,1.18,0),(2.12,.15,1.35),CREAM,.05)
        m.box((0,.68,.59),(1.4,.38,.03),DARK,.055)
        m.box((-.37,.68,.615),(.52,.23,.015),'678d99',.03)
        for x,tint in [(.35,'e4b858'),(.6,'98ba7a')]:m.lathe((x,.68,.635),[(0,.065),(.04,.065)],tint,12,rot=(math.pi/2,0,0))
        spinner=m.node('Spinner',(0,1.5,-.15))
        if name=='coffee_roaster':
            m.lathe((-.25,1.55,-.1),[(-.38,.36),(.2,.36),(.28,.3)],'c49b5b',20,rot=(math.pi/2,0,0),material='Metal')
            m.ring((-.25,1.55,.24),.3,.035,DARK,rot=(math.pi/2,0,0))
            m.lathe((.62,1.65,-.25),[(0,.1),(.28,.14),(.6,.35)],STEEL,16,material='Metal')
            m.box((.7,1.4,.38),(.5,.1,.38),DARK)
            m.node('StockAnchor',(0,1.29,.55))
            m.box((0,0,0),(.7,.06,.13),STEEL,parent=spinner)
        elif name=='juice_press':
            m.lathe((-.32,1.25,-.15),[(0,.3),(.9,.3),(1,.26)],'d1e7e4',material='Glass')
            m.lathe((-.32,1.25,-.15),[(0,.28),(.55,.28)],'eaa646')
            m.lathe((-.32,2.27,-.15),[(0,.3),(.1,.3)],accent)
            m.pipe((-.32,1.4,.13),(.18,1.4,.45),.05,STEEL)
            m.pipe((.18,1.4,.45),(.18,1.2,.45),.05,STEEL)
            m.box((0,0,0),(.47,.05,.1),STEEL,parent=spinner)
            m.node('StockAnchor',(.28,1.27,.35))
        elif name=='recycler':
            m.lathe((-.35,1.27,-.13),[(0,.22),(.5,.55),(.61,.55)],'6f858f',12)
            m.lathe((-.35,1.9,-.13),[(0,.48),(.015,.48)],DARK,12)
            for i in range(5):m.box((.72,1.27,-.45+i*.2),(.54,.07,.13),DARK,.015)
            m.lathe((0,0,0),[(-.05,.23),(.05,.23)],STEEL,12,parent=spinner)
            for i in range(8):m.box((math.cos(i*TAU/8)*.24,0,math.sin(i*TAU/8)*.24),(.12,.12,.12),DARK,.02,parent=spinner)
            m.node('StockAnchor',(.5,1.39,.3))
        else:
            m.box((-.22,1.3,0),(1.12,.14,.9),DARK,.06)
            m.box((-.22,1.39,0),(.91,.05,.71),'dca741' if name=='donut_fryer' else '704839',.06)
            for x in [-.47,.03]:m.ring((x,1.42,0),.13,.055,'e6be71' if name=='donut_fryer' else '94553e')
            m.lathe((.72,1.46,-.25),[(0,.16),(.18,.2),(.4,.29)],STEEL,material='Metal')
            m.pipe((.73,1.6,-.1),(.65,1.6,.34),.045,STEEL)
            m.box((0,.07,0),(.78,.07,.12),STEEL,parent=spinner)
            m.node('StockAnchor',(.62,1.28,.3))
    elif name in ('market_stall','coffee_counter','bakery_counter','parts_counter'):
        accent={'market_stall':GREEN,'coffee_counter':'76918a','bakery_counter':PINK,'parts_counter':'738d97'}[name]
        m.box((0,.6,0),(2.45,1.15,1.12),WOOD if name in ('market_stall','coffee_counter') else accent,.09)
        for i in range(9):m.box((-.99+i*.25,.58,.59),(.035,.9,.025),LIGHTWOOD if name in ('market_stall','coffee_counter') else 'eac2b8',.008)
        m.box((0,1.19,0),(2.65,.17,1.35),CREAM,.06)
        register(m)
        if name=='market_stall':
            for x in [-1.12,1.12]:m.box((x,1.4,-.47),(.09,2.8,.09),WOOD)
            for i in range(6):
                tint=GREEN if i%2 else CREAM
                m.box((-1.1+i*.44,2.73,-.35),(.46,.08,1.15),tint,.015,rot=(-.17,0,0))
                m.box((-1.1+i*.44,2.63,.22),(.46,.22,.04),tint,.015)
            crate(m,(-.35,1.31,.28),1.35,.6)
            m.node('StockAnchor',(-.28,1.43,.27))
        elif name=='bakery_counter':
            for x in [-1.02,.28]:m.pipe((x,1.28,-.4),(x,1.85,-.4),.035,STEEL)
            m.box((-.37,1.77,0),(1.42,.045,.92),STEEL,.02)
            m.box((-.37,1.59,.46),(1.36,.41,.025),'d4eef1',.006,material='Glass')
            for x in [-1.05,.31]:m.box((x,1.56,0),(.025,.45,.92),'d4eef1',.006,material='Glass')
            m.ring((0,.6,.59),.22,.065,'e5ba71',rot=(math.pi/2,0,0))
            m.ring((0,.6,.62),.22,.045,PINK,rot=(math.pi/2,0,0))
            m.node('StockAnchor',(-.35,1.38,.05))
        elif name=='coffee_counter':
            m.box((-.63,1.52,-.25),(.9,.64,.56),'cbd5d6',.06)
            m.box((-.63,1.66,.055),(.68,.21,.035),DARK)
            for x in [-.88,-.4]:
                m.pipe((x,1.55,.04),(x,1.55,.3),.036,STEEL)
                m.pipe((x,1.4,.26),(x,1.5,.26),.032,DARK)
            m.lathe((.11,1.45,-.3),[(0,.12),(.28,.12),(.36,.18)],STEEL,material='Metal')
            m.node('StockAnchor',(-.35,1.31,.39))
        else:
            m.box((0,1.85,-.5),(2.3,1.3,.1),LIGHTWOOD)
            for x in [-.9,-.45,0,.45,.9]:
                for y in [1.55,1.9,2.25]:m.lathe((x,y,-.43),[(0,.022),(.025,.022)],DARK,8,rot=(math.pi/2,0,0))
            m.pipe((-.65,1.4,-.36),(-.65,2.0,-.36),.05,WOOD)
            m.box((-.65,2.04,-.36),(.45,.16,.14),STEEL)
            m.pipe((.1,1.5,-.34),(.1,2.1,-.34),.035,STEEL)
            m.ring((.1,2.13,-.34),.1,.03,STEEL,rot=(math.pi/2,0,0))
            m.node('StockAnchor',(-.28,1.36,.25))
    elif name=='table_set':table(m)
    elif name=='staff_locker':
        m.box((0,.78,-.15),(1.45,1.5,.7),'80a5a0',.06)
        for x in [-.37,.37]:
            m.box((x,.8,.215),(.66,1.36,.035),'94b4ad',.025)
            m.box((x+.2,.75,.25),(.045,.18,.05),STEEL,.01)
            for y in [1.18,1.26,1.34]:m.box((x,y,.24),(.42,.025,.02),DARK,.003)
        m.box((0,.37,.58),(1.72,.12,.44),LIGHTWOOD)
        for x in [-.62,.62]:m.box((x,.17,.58),(.08,.34,.34),DARK,.02)
    elif name=='planter':planter(m,(0,0,0))
    elif name=='shade_tree':
        m.lathe((0,0,0),[(0,.2),(.2,.15),(1.8,.08)],WOOD,10)
        for x,y,z,r in [(-.45,1.8,0,.65),(.35,2.0,.2,.75),(0,2.45,0,.75),(0,2.0,-.4,.65)]:m.ball((x,y,z),r,['76a866','8ab46e'][int(y*10)%2])
    elif name=='delivery_van':
        m.box((0,.78,0),(1.65,1.12,3.05),'b6ceba',.15)
        m.box((0,1.3,.7),(1.6,.6,1.12),'d5e2cd',.12)
        m.box((0,1.46,1.15),(1.36,.38,.05),'5d7c8a',.03,rot=(-.2,0,0))
        m.box((0,.46,1.56),(1.69,.15,.12),DARK)
        for x in [-.57,.57]:m.box((x,.8,1.55),(.28,.16,.055),'f5df9b')
        for x in [-.83,.83]:
            for z in [-.96,.92]:
                m.lathe((x,.38,z),[(-.08,.31),(.08,.31)],'34454c',16,rot=(0,0,math.pi/2))
                m.lathe((x*1.06,.38,z),[(-.025,.17),(.025,.17)],STEEL,12,rot=(0,0,math.pi/2))
    else:raise ValueError(name)
    return m


def main():
    names=['tomato_plot','orchard_tree','ingredient_pallet','coffee_delivery','scrap_bin','donut_fryer','chocolate_glazer','coffee_roaster','juice_press','recycler','market_stall','coffee_counter','bakery_counter','parts_counter','table_set','staff_locker','planter','shade_tree','delivery_van']
    models=[station_model(n) for n in names]+[character()]+[item_model(n) for n in ['tomato','apple','beans','dough','coffee','juice','scrap','parts','donut','chocolate_donut','cash_bundle']]
    manifest=[m.save() for m in models]
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'Authored {len(models)} GLB models; {sum(m["triangles"] for m in manifest):,} triangles in the full kit')

if __name__=='__main__':main()
