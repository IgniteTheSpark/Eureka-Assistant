from evals.scenarios import SCENARIOS


def main() -> None:
    failed = []
    for scenario in SCENARIOS:
        try:
            passed = scenario.evaluate()
        except Exception as exc:
            passed = False
            print(f"FAIL {scenario.name}: {type(exc).__name__}")
        else:
            print(f"{'PASS' if passed else 'FAIL'} {scenario.name}")
        if not passed:
            failed.append(scenario.name)
    print(f"{len(SCENARIOS) - len(failed)}/{len(SCENARIOS)} scenarios passed")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
