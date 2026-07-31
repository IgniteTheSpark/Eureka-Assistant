from app.domains.reports.shares import hash_share_token, issue_share_token


def test_share_tokens_are_random_url_safe_and_only_hash_is_stable():
    first = issue_share_token()
    second = issue_share_token()

    assert first != second
    assert len(first) >= 43
    assert len(second) >= 43
    assert "/" not in first and "+" not in first
    assert hash_share_token(first) == hash_share_token(first)
    assert hash_share_token(first) != hash_share_token(second)
    assert len(hash_share_token(first)) == 64
    assert first not in hash_share_token(first)
