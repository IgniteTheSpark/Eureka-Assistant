"""
One-off demo data — manual entries spanning 2026-05-15 … 2026-06-05.

Everything is created WITHOUT a session_id / source_input_turn_id, so the
app treats each as 「手动创建」 (not agent-made). Assets get an explicit
backdated created_at so the timeline spreads across the window. Events use
start_at for timeline position; contacts are backdated too.

Run:  docker compose exec -T backend python -m db.seed_demo
Idempotent-ish: re-running ADDS another batch, so only run on a clean DB.
"""
import asyncio
import uuid
from datetime import datetime, timezone, timedelta

from sqlalchemy import select

from db.database import AsyncSessionLocal
from db.models import Asset, Contact, Event, UserSkill, GlobalSkill
from db.queries import index_asset_fields

TZ = timezone(timedelta(hours=8))  # +08:00


def dt(month, day, hour=9, minute=0):
    return datetime(2026, month, day, hour, minute, tzinfo=TZ)


async def _skill_ids(db, user_id="default"):
    rows = (await db.execute(
        select(UserSkill, GlobalSkill.name)
        .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
        .where(UserSkill.user_id == user_id)
    )).all()
    return {name: us.id for us, name in rows}


async def main():
    user_id = "default"
    async with AsyncSessionLocal() as db:
        sk = await _skill_ids(db, user_id)

        # ── Assets (manual: session_id=None), backdated created_at ──────────
        # (skill, created_at, payload)
        assets = [
            # todo — timeline uses due_date
            ("todo", dt(5, 16, 9, 0),  {"content": "交五月房租",          "due_date": dt(5,16,18,0).isoformat(), "status": "done"}),
            ("todo", dt(5, 20, 9, 0),  {"content": "给妈妈买生日礼物",      "due_date": dt(5,20,20,0).isoformat(), "status": "pending"}),
            ("todo", dt(5, 28, 9, 0),  {"content": "提交季度报告",          "due_date": dt(5,28,17,0).isoformat(), "status": "done"}),
            ("todo", dt(6, 2,  9, 0),  {"content": "预约体检",              "due_date": dt(6,2,10,0).isoformat(),  "status": "pending"}),
            ("todo", dt(6, 5,  9, 0),  {"content": "续签健身卡",            "due_date": dt(6,5,12,0).isoformat(),  "status": "pending"}),

            # expense — timeline uses `at`
            ("expense", dt(5,15,8,40),  {"amount": 38,  "merchant": "星巴克",   "category": "餐饮", "at": dt(5,15,8,40).isoformat()}),
            ("expense", dt(5,19,18,12), {"amount": 56,  "merchant": "滴滴出行", "category": "交通", "at": dt(5,19,18,12).isoformat()}),
            ("expense", dt(5,23,21,5),  {"amount": 499, "merchant": "京东(机械键盘)", "category": "数码", "at": dt(5,23,21,5).isoformat()}),
            ("expense", dt(5,26,19,30), {"amount": 213, "merchant": "永辉超市", "category": "生活", "at": dt(5,26,19,30).isoformat()}),
            ("expense", dt(5,30,20,10), {"amount": 420, "merchant": "海底捞",   "category": "餐饮", "at": dt(5,30,20,10).isoformat()}),
            ("expense", dt(6,1,15,0),   {"amount": 90,  "merchant": "万达影城", "category": "娱乐", "at": dt(6,1,15,0).isoformat()}),

            # idea — timeline uses created_at
            ("idea", dt(5,17,22,30), {"content": "做一个家庭账本共享功能,夫妻俩能合并看支出"}),
            ("idea", dt(5,24,8,15),  {"content": "让 AI 每周自动生成一份生活复盘,周日早上推给我"}),
            ("idea", dt(6,2,23,0),   {"content": "给 app 加一个『每日心情打卡』,年底能看到情绪曲线"}),

            # notes — timeline uses created_at
            ("notes", dt(5,21,16,0), {"title": "Q2 复盘要点", "content": "营收同比 +32%;新客主要来自社交媒体;重点城市继续拓展;Q3 聚焦留存。"}),
            ("notes", dt(5,29,21,40),{"title": "读《纳瓦尔宝典》", "content": "财富是睡觉时也能赚的资产;用判断力而非苦力赚钱;长期博弈与长期的人。"}),

            # misc
            ("misc", dt(5,25,12,0),  {"content": "楼下新开的那家面馆不错,牛肉面很赞"}),
        ]

        for skill_name, created_at, payload in assets:
            usid = sk.get(skill_name)
            if not usid:
                print(f"  ! skip {skill_name} (skill not registered)")
                continue
            asset = Asset(
                id=uuid.uuid4(),
                user_id=user_id,
                user_skill_id=usid,
                session_id=None,            # manual
                source_input_turn_id=None,  # manual
                payload=payload,
                created_at=created_at,
            )
            db.add(asset)
            await db.flush()
            await index_asset_fields(db, asset.id, user_id, usid, payload)
        await db.commit()
        print(f"  + {len(assets)} assets")

        # ── Events (manual) ────────────────────────────────────────────────
        events = [
            ("产品评审会",   dt(5,18,14,0), dt(5,18,15,30), "会议室 A"),
            ("牙医复诊",     dt(5,22,10,0), dt(5,22,11,0),  "微笑口腔(浦东店)"),
            ("老王生日饭",   dt(5,27,19,0), dt(5,27,21,0),  "海底捞(陆家嘴)"),
            ("客户路演",     dt(6,3,9,30),  dt(6,3,12,0),   "浦东软件园 3 号楼"),
        ]
        for title, start, end, loc in events:
            db.add(Event(
                id=uuid.uuid4(), user_id=user_id, title=title,
                start_at=start, end_at=end, all_day=0, location=loc,
                source_input_turn_id=None, created_at=start,
            ))
        await db.commit()
        print(f"  + {len(events)} events")

        # ── Contacts (manual) ──────────────────────────────────────────────
        contacts = [
            ("王磊", "13800138000", "蓝鲸科技", "产品总监",  "wanglei@lanjing.com", dt(5,18,15,40)),
            ("林晓", "13900139000", "自由职业", "独立设计师", "lin@studio.cn",       dt(5,20,11,0)),
            ("陈航", "13700137000", "华兴资本", "投资经理",  "chen@huaxing.com",   dt(6,3,12,10)),
        ]
        for name, phone, company, title, email, created in contacts:
            db.add(Contact(
                id=uuid.uuid4(), user_id=user_id, name=name, phone=phone,
                company=company, title=title, email=email, notes=[],
                created_at=created,
            ))
        await db.commit()
        print(f"  + {len(contacts)} contacts")

    print("Demo seed complete (2026-05-15 … 2026-06-05, all manual).")


if __name__ == "__main__":
    asyncio.run(main())
