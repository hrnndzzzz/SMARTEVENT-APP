"""The receipt scan suggests one of the scanned organization's own categories, and nothing else."""

from app.models import Category
from app.test_access_management import system


def scan(client, monkeypatch, answer):
    offered = []

    def parse(image, content_type, category_names):
        offered.extend(category_names)
        return {"merchant": "Store", "date": None, "amount": 10, "items": [], "expense_category": answer}

    monkeypatch.setattr("app.routers.expenses.prepare_image_for_upload", lambda raw: (raw, "image/jpeg"))
    monkeypatch.setattr("app.routers.expenses.upload_receipt_image", lambda *args: "https://example.com/r.jpg")
    monkeypatch.setattr("app.routers.expenses.parse_receipt_image", parse)
    response = client.post("/expenses/scan-receipt", files={"file": ("r.jpg", b"image", "image/jpeg")})
    assert response.status_code == 200, response.text
    return response.json()["suggested_category_id"], offered


def test_a_matching_name_is_suggested_by_id(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    food = Category(name="Food and Drinks", organization_id=orgs[0].id, department_id=orgs[0].department_id,
                    allocated_budget=0, remaining_budget=0)
    db.add(food)
    db.commit()
    login("officer")  # Organization A's

    suggested, offered = scan(client, monkeypatch, "food and drinks")

    assert suggested == str(food.id)
    assert sorted(offered) == ["Food and Drinks", "Supplies"]  # Organization B's "Supplies" is not offered twice


def test_an_unlisted_or_missing_answer_suggests_nothing(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    login("officer")
    assert scan(client, monkeypatch, "Catering")[0] is None
    assert scan(client, monkeypatch, None)[0] is None
