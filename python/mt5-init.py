import MetaTrader5 as mt5
import os
import sys
from datetime import datetime

from i18n import t


def initialize_mt5(terminal_path=None):
    """
    Initialize MetaTrader 5 connection with error handling

    Args:
        terminal_path (str): Path to MT5 terminal executable

    Returns:
        bool: True if initialization successful, False otherwise
    """
    try:
        if not terminal_path:
            if not mt5.initialize():
                common_paths = [
                    "C:\\Program Files\\MetaTrader 5\\terminal64.exe",
                    "C:\\Program Files (x86)\\MetaTrader 5\\terminal64.exe",
                    "C:\\Users\\{}\\AppData\\Roaming\\MetaQuotes\\Terminal\\*\\terminal64.exe".format(os.getenv('USERNAME'))
                ]

                for path in common_paths:
                    if os.path.exists(path):
                        if mt5.initialize(path):
                            print(t("mt5_init_ok_path", path=path))
                            return True

                print(t("mt5_init_fail_default"))
                return False
        else:
            if not mt5.initialize(terminal_path):
                print(t("mt5_init_fail_path", path=terminal_path))
                print(t("mt5_last_error", err=mt5.last_error()))
                return False

        account_info = mt5.account_info()
        if account_info is None:
            print(t("mt5_no_account"))
            return False

        print(t("mt5_init_ok"))
        print(t("mt5_connected_account", login=account_info.login))
        print(t("mt5_server", server=account_info.server))
        print(t("mt5_conn_time", t=datetime.now().strftime('%Y-%m-%d %H:%M:%S')))

        return True

    except Exception as e:
        print(t("mt5_exception", e=e))
        return False


def main():
    """Main function to initialize MT5"""
    if not initialize_mt5():
        print(t("mt5_trouble_title"))
        print(t("mt5_trouble_1"))
        print(t("mt5_trouble_2"))
        print(t("mt5_trouble_3"))
        print(t("mt5_trouble_4"))
        sys.exit(1)

    print(t("mt5_done"))


if __name__ == "__main__":
    main()
