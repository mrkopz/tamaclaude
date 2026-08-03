# TamaClaude

อุปกรณ์ตั้งโต๊ะที่บอกสถานะ session ของ Claude Code ด้วยมาสคอตบนจอ 320×240 และ (ตั้งแต่รอบ
multi-page) ใช้จอเดียวกันนั้นแสดงข้อมูลเฝ้าดูอย่างอื่นด้วย เอกสารนี้เป็น**อภิธานศัพท์**อย่างเดียว —
เหตุผลเชิงออกแบบอยู่ใน `DESIGN.md` ส่วนการตัดสินใจที่ย้อนยาก อยู่ใน `docs/adr/`

## ผู้เล่นหลัก

**Board**:
เครื่อง ESP32 พร้อมจอที่วางบนโต๊ะ วาดสิ่งที่ Mac ส่งมา ไม่ตัดสินใจเนื้อหาเอง และไม่เชื่อมต่อ
อินเทอร์เน็ตด้วยตัวเอง
_Avoid_: device, จอ, CYD

**Daemon**:
กระบวนการบน Mac ที่เป็นเจ้าของตรรกะทั้งหมด — รับ hook, ดึงข้อมูลภายนอก, ประกอบสิ่งที่จะแสดง
แล้วส่งให้ board (ในทางกายภาพมันคือแอป menu bar ตัวเดียวกัน)
_Avoid_: server, host process, agent

**Session**:
การทำงานหนึ่งครั้งของ Claude Code ที่ยิง hook เข้ามา ระบุด้วย session id และผูกกับหนึ่งโปรเจกต์
_Avoid_: conversation, run, job

## สิ่งที่จอแสดง

**Page**:
หนึ่งหน้าจอเต็มที่ผู้ใช้เปลี่ยนไปมาได้ หนึ่งหน้าเล่าเรื่องเดียว (มาสคอต, หุ้น, คริปโต, อากาศ, ปฏิทิน)
_Avoid_: screen, tab, view, mode

**PageKind**:
ชนิดของ page เป็นชุดปิดที่ board รู้จักตั้งแต่ตอนแฟลช ไม่ใช่สิ่งที่ Mac นิยามขึ้นตอนรันไทม์
_Avoid_: page type, widget type, template

**Active page**:
page ที่กำลังแสดงอยู่จริง ณ ขณะนั้น board เป็นเจ้าของค่านี้ ไม่ใช่ Mac
_Avoid_: current screen, selected page

**Page frame**:
ก้อนข้อมูลของ page เดียวที่เดินทางจาก Mac ไป board หนึ่งเฟรมพูดถึงหน้าเดียวและต้องพอดีหนึ่ง MTU
_Avoid_: packet, message, payload

**Snapshot**:
page frame ของหน้ามาสคอตโดยเฉพาะ — คำที่มีอยู่ก่อนรอบ multi-page และยังหมายถึงหน้านั้นหน้าเดียว
_Avoid_: state, screen state

**Pose**:
ท่าทางหนึ่งของมาสคอตที่ตรงกับ `VisualState` หนึ่งค่า ทุก pose มีอายุขั้นต่ำก่อนถูกแทนที่
_Avoid_: animation, frame, sprite

**Card**:
กล่องข้อความชั่วคราวบนหน้ามาสคอตที่รายงานเหตุการณ์ของ session เช่นคำถามที่รออนุญาต
_Avoid_: notification, toast, banner

**Quota window**:
ช่วงเวลาการใช้งาน Claude หนึ่งหน้าต่าง (ห้าชั่วโมง หรือเจ็ดวัน) ที่มีเปอร์เซ็นต์ใช้ไปและเวลารีเซ็ต
_Avoid_: usage, limit, rate limit

## พฤติกรรมของ page

**Page rotation**:
การที่ board เปลี่ยน active page เองตามเวลาที่ตั้งไว้ board เป็นคนจับเวลา Mac ส่งแค่ค่าตั้ง
_Avoid_: slideshow, carousel, cycling

**Manual hold**:
ช่วงเวลาที่ page rotation หยุดชั่วคราวเพราะผู้ใช้เพิ่ง swipe — เป็นการประกาศว่า "กำลังดูหน้านี้อยู่"
_Avoid_: pause, lock, pin

**Attention jump**:
การที่ board สลับไปหน้ามาสคอตเองเพราะมีเหตุการณ์ที่ต้องการคน เกิดได้ครั้งเดียวต่อหนึ่งเหตุการณ์
_Avoid_: alert, interrupt, force switch

**Data age**:
เวลาที่ผ่านไปนับจากตอนที่ Mac ได้ข้อมูลของ page นั้นมาจริง board นับต่อเองได้แม้ขาดการเชื่อมต่อ
_Avoid_: timestamp, last updated, freshness

**Board capability**:
รายการ PageKind ที่ board ตัวนั้นรู้จัก ประกาศจาก board ไป Mac ตอนเชื่อมต่อ ใช้แทนเลขเวอร์ชัน
_Avoid_: firmware version, protocol version, feature flag

## แหล่งข้อมูล

**Watchlist**:
รายชื่อสัญลักษณ์ที่ผู้ใช้เลือกให้แสดงบน page หนึ่ง (หุ้น หรือ คริปโต) มีเพดานจำนวนบังคับ
_Avoid_: portfolio, symbols, tickers

**Second path**:
เส้นทาง TCP ผ่าน LAN ที่ถูกใช้เมื่อ BLE เงียบเกินเวลาที่กำหนด ปลายทางคือ board เครื่องเดิม
_Avoid_: fallback, WiFi mode, backup link

## ข้อความบนจอ

**Cluster**:
กลุ่มอักขระไทยที่วาดซ้อนกันในหนึ่งช่อง — พยัญชนะฐาน บวกสระบน/ล่าง บวกวรรณยุกต์ Mac เดินทีละ
cluster เพื่อเลือกร่างของ glyph ก่อนส่งให้ board
_Avoid_: grapheme, character group, syllable

**Glyph variant**:
ร่างหนึ่งของสระบนหรือวรรณยุกต์ที่อยู่คนละระดับความสูง เลือกตามพยัญชนะฐานและสิ่งที่ซ้อนอยู่แล้ว
_Avoid_: alternate, form, shifted glyph

**Display width**:
ความกว้างของข้อความนับเฉพาะอักขระที่กินที่จริง — สระบนและวรรณยุกต์กว้างศูนย์ จึงไม่ถูกนับ
_Avoid_: length, character count
