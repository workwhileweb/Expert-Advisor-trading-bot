import MetaTrader5 as mt5
import sys
from datetime import datetime

from i18n import t


def get_detailed_account_info():
    """
    Get comprehensive account information with error handling

    Returns:
        dict: Account information or None if failed
    """
    try:
        if not mt5.initialize():
            print(t("account_init_failed", err=mt5.last_error()))
            return None

        account_info = mt5.account_info()
        if account_info is None:
            print(t("account_get_failed"))
            print(t("account_last_error", err=mt5.last_error()))
            return None

        account_data = {
            'login': account_info.login,
            'server': account_info.server,
            'name': account_info.name,
            'company': account_info.company,
            'currency': account_info.currency,
            'balance': account_info.balance,
            'equity': account_info.equity,
            'margin': account_info.margin,
            'free_margin': account_info.margin_free,
            'margin_level': account_info.margin_level,
            'profit': account_info.profit,
            'trade_allowed': account_info.trade_allowed,
            'trade_expert': account_info.trade_expert,
            'leverage': account_info.leverage,
            'margin_so_mode': account_info.margin_so_mode,
            'margin_so_call': account_info.margin_so_call,
            'margin_so_so': account_info.margin_so_so
        }

        return account_data

    except Exception as e:
        print(t("account_exception", e=e))
        return None


def print_account_summary(account_data):
    """
    Print formatted account summary

    Args:
        account_data (dict): Account information dictionary
    """
    if not account_data:
        print(t("account_no_data"))
        return

    cur = account_data['currency']
    yn_yes = t("yes_no_yes")
    yn_no = t("yes_no_no")

    print("\n" + "="*50)
    print(t("account_title"))
    print("="*50)
    print(t("account_id", v=account_data['login']))
    print(t("account_server", v=account_data['server']))
    print(t("account_company", v=account_data['company']))
    print(t("account_name", v=account_data['name']))
    print(t("account_currency", v=account_data['currency']))
    print(t("account_leverage", v=account_data['leverage']))
    print("\n" + "-"*30)
    print(t("account_financial"))
    print("-"*30)
    print(t("account_balance", v=account_data['balance'], cur=cur))
    print(t("account_equity", v=account_data['equity'], cur=cur))
    print(t("account_profit", v=account_data['profit'], cur=cur))
    print(t("account_free_margin", v=account_data['free_margin'], cur=cur))
    print(t("account_margin_level", v=account_data['margin_level']))
    print("\n" + "-"*30)
    print(t("account_trading_status"))
    print("-"*30)
    print(t("account_trade_allowed", v=yn_yes if account_data['trade_allowed'] else yn_no))
    print(t("account_trade_expert", v=yn_yes if account_data['trade_expert'] else yn_no))
    print(t("account_last_updated", v=datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
    print("="*50)


def check_trading_conditions(account_data):
    """
    Check if account is ready for trading

    Args:
        account_data (dict): Account information dictionary

    Returns:
        bool: True if ready for trading, False otherwise
    """
    if not account_data:
        return False

    warnings = []
    errors = []

    if not account_data['trade_allowed']:
        errors.append(t("account_err_trade_disabled"))

    if not account_data['trade_expert']:
        errors.append(t("account_err_expert_disabled"))

    if account_data['margin_level'] < 100:
        errors.append(t("account_err_margin_low", v=account_data['margin_level']))
    elif account_data['margin_level'] < 200:
        warnings.append(t("account_warn_margin_low", v=account_data['margin_level']))

    if account_data['free_margin'] < 100:
        warnings.append(t("account_warn_free_margin", v=account_data['free_margin']))

    if warnings:
        print(t("account_warn_header"))
        for warning in warnings:
            print(f"   - {warning}")

    if errors:
        print(t("account_err_header"))
        for error in errors:
            print(f"   - {error}")
        return False

    if not warnings and not errors:
        print(t("account_ready"))

    return True


def main():
    """Main function"""
    try:
        print(t("account_retrieving"))
        account_data = get_detailed_account_info()

        if account_data:
            print_account_summary(account_data)
            check_trading_conditions(account_data)
        else:
            print(t("account_failed_retrieve"))
            print(t("account_please_ensure"))
            print(t("account_ensure_1"))
            print(t("account_ensure_2"))
            print(t("account_ensure_3"))
            sys.exit(1)

    except KeyboardInterrupt:
        print(t("account_cancelled"))
    except Exception as e:
        print(t("account_unexpected", e=e))
        sys.exit(1)
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    main()
