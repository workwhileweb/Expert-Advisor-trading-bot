import MetaTrader5 as mt5
import sys
from datetime import datetime
import time

from i18n import t


def test_connection():
    """
    Test MT5 connection and basic functionality

    Returns:
        bool: True if all tests pass, False otherwise
    """
    tests_passed = 0
    total_tests = 5
    sep = t("it_sep")

    print(t("it_running_tests"))
    print(sep)

    print(t("it_test1"), end="")
    try:
        if mt5.initialize():
            print(t("it_passed"))
            tests_passed += 1
        else:
            print(t("it_failed"))
            print(t("it_err", err=mt5.last_error()))
    except Exception as e:
        print(t("it_failed"))
        print(t("it_exception", e=e))

    print(t("it_test2"), end="")
    try:
        terminal_info = mt5.terminal_info()
        if terminal_info:
            print(t("it_passed"))
            print(t("it_build", v=terminal_info.build))
            print(t("it_path", v=terminal_info.path))
            tests_passed += 1
        else:
            print(t("it_failed"))
    except Exception as e:
        print(t("it_failed"))
        print(t("it_exception", e=e))

    print(t("it_test3"), end="")
    try:
        account_info = mt5.account_info()
        if account_info:
            print(t("it_passed"))
            print(t("it_account", v=account_info.login))
            print(t("it_server", v=account_info.server))
            print(t("it_currency", v=account_info.currency))
            tests_passed += 1
        else:
            print(t("it_failed"))
    except Exception as e:
        print(t("it_failed"))
        print(t("it_exception", e=e))

    print(t("it_test4"), end="")
    try:
        symbols_to_test = ["EURUSD", "GBPUSD", "USDJPY"]
        successful_symbols = 0

        for symbol in symbols_to_test:
            tick = mt5.symbol_info_tick(symbol)
            if tick:
                successful_symbols += 1

        if successful_symbols > 0:
            print(t("it_passed"))
            print(t("it_symbols_ok", n=successful_symbols, t=len(symbols_to_test)))
            tests_passed += 1
        else:
            print(t("it_failed"))
            print(t("it_no_symbol_data"))
    except Exception as e:
        print(t("it_failed"))
        print(t("it_exception", e=e))

    print(t("it_test5"), end="")
    try:
        account_info = mt5.account_info()
        if account_info:
            if account_info.trade_allowed and account_info.trade_expert:
                print(t("it_passed"))
                print(t("it_ea_ok_msg"))
                tests_passed += 1
            else:
                print(t("it_partial"))
                print(t("it_trade_allowed", v=account_info.trade_allowed))
                print(t("it_ea_allowed", v=account_info.trade_expert))
        else:
            print(t("it_failed"))
    except Exception as e:
        print(t("it_failed"))
        print(t("it_exception", e=e))

    print(t("it_tests_done", sep=sep, p=tests_passed, t=total_tests))

    return tests_passed == total_tests


def get_market_data(symbols=None):
    """
    Get current market data for specified symbols

    Args:
        symbols (list): List of symbols to get data for
    """
    if symbols is None:
        symbols = ["EURUSD", "GBPUSD", "USDJPY"]

    print(t("it_market_title"))
    print(t("it_market_sep"))
    h_sym = t("it_col_symbol")
    h_bid = t("it_col_bid")
    h_ask = t("it_col_ask")
    h_spr = t("it_col_spread")
    h_time = t("it_col_time")
    print(f"{h_sym:<10} {h_bid:<10} {h_ask:<10} {h_spr:<10} {h_time:<20}")
    print(t("it_market_dash"))

    na = t("it_na")

    for symbol in symbols:
        try:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info and not symbol_info.visible:
                mt5.symbol_select(symbol, True)

            tick = mt5.symbol_info_tick(symbol)
            if tick:
                spread = (tick.ask - tick.bid) / mt5.symbol_info(symbol).point
                timestamp = datetime.fromtimestamp(tick.time).strftime('%H:%M:%S')
                print(f"{symbol:<10} {tick.bid:<10.5f} {tick.ask:<10.5f} {spread:<10.1f} {timestamp:<20}")
            else:
                print(f"{symbol:<10} {na:<10} {na:<10} {na:<10} {na:<20}")
        except Exception as e:
            err_short = str(e)[:40]
            line = t("it_symbol_error", sym=symbol, err=err_short)
            print(line)


def check_system_requirements():
    """
    Check system requirements and settings
    """
    print(t("it_sys_title"))
    print(t("it_sep"))

    try:
        terminal_info = mt5.terminal_info()
        if terminal_info:
            print(t("it_sys_build", v=terminal_info.build))
            print(t("it_sys_dll", v=terminal_info.dlls_allowed))
            print(t("it_sys_trade", v=terminal_info.trade_allowed))
            print(t("it_sys_connected", v=terminal_info.connected))

            if not terminal_info.dlls_allowed:
                print(t("it_warn_dll"))
            if not terminal_info.trade_allowed:
                print(t("it_warn_trade"))
            if not terminal_info.connected:
                print(t("it_err_connect"))

    except Exception as e:
        print(t("it_sys_check_err", e=e))


def main():
    """
    Main function to run all tests
    """
    try:
        print(t("it_script_title"))
        print(t("it_started", v=datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
        print(t("it_sep50"))

        if test_connection():
            print(t("it_all_pass"))

            get_market_data()

            check_system_requirements()

        else:
            print(t("it_some_fail"))
            print(t("it_trouble_title"))
            print(t("it_trouble_1"))
            print(t("it_trouble_2"))
            print(t("it_trouble_3"))
            print(t("it_trouble_4"))
            print(t("it_trouble_5"))

    except KeyboardInterrupt:
        print(t("it_cancelled"))
    except Exception as e:
        print(t("it_unexpected", e=e))
    finally:
        print(t("it_completed", v=datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
        mt5.shutdown()


if __name__ == "__main__":
    main()
