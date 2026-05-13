import MetaTrader5 as mt5
import sys
from datetime import datetime

from i18n import t


def validate_symbol(symbol):
    """
    Validate if symbol is available for trading

    Args:
        symbol (str): Trading symbol

    Returns:
        bool: True if valid, False otherwise
    """
    symbol_info = mt5.symbol_info(symbol)
    if symbol_info is None:
        print(t("tf_symbol_not_found", sym=symbol))
        return False

    if not symbol_info.visible:
        print(t("tf_symbol_not_visible", sym=symbol))
        if not mt5.symbol_select(symbol, True):
            print(t("tf_symbol_add_fail", sym=symbol))
            return False

    return True


def calculate_safe_lot_size(symbol, risk_amount, stop_loss_pips):
    """
    Calculate lot size based on risk amount and stop loss

    Args:
        symbol (str): Trading symbol
        risk_amount (float): Risk amount in account currency
        stop_loss_pips (int): Stop loss in pips

    Returns:
        float: Calculated lot size
    """
    min_lot = 0.01
    try:
        symbol_info = mt5.symbol_info(symbol)
        if symbol_info is None:
            return 0.01

        tick_value = symbol_info.trade_tick_value
        tick_size = symbol_info.trade_tick_size
        min_lot = symbol_info.volume_min
        max_lot = symbol_info.volume_max
        lot_step = symbol_info.volume_step

        pip_value = tick_value * (0.0001 / tick_size)
        if symbol.endswith('JPY'):
            pip_value = tick_value * (0.01 / tick_size)

        lot_size = risk_amount / (stop_loss_pips * pip_value)

        lot_size = round(lot_size / lot_step) * lot_step

        lot_size = max(min_lot, min(lot_size, max_lot))

        return lot_size

    except Exception as e:
        print(t("tf_lot_error", e=e))
        return min_lot


def _retcode_messages():
    return {
        mt5.TRADE_RETCODE_INVALID_VOLUME: t("tf_err_invalid_volume"),
        mt5.TRADE_RETCODE_INVALID_PRICE: t("tf_err_invalid_price"),
        mt5.TRADE_RETCODE_INVALID_STOPS: t("tf_err_invalid_stops"),
        mt5.TRADE_RETCODE_TRADE_DISABLED: t("tf_err_trade_disabled"),
        mt5.TRADE_RETCODE_MARKET_CLOSED: t("tf_err_market_closed"),
        mt5.TRADE_RETCODE_NO_MONEY: t("tf_err_no_money"),
        mt5.TRADE_RETCODE_PRICE_CHANGED: t("tf_err_price_changed"),
        mt5.TRADE_RETCODE_REJECT: t("tf_err_reject"),
        mt5.TRADE_RETCODE_INVALID_FILL: t("tf_err_invalid_fill"),
    }


def place_test_order(symbol="EURUSD", order_type="BUY", risk_amount=50.0):
    """
    Place a test order with proper error handling

    Args:
        symbol (str): Trading symbol
        order_type (str): Order type (BUY/SELL)
        risk_amount (float): Risk amount in account currency

    Returns:
        bool: True if successful, False otherwise
    """
    try:
        if not mt5.initialize():
            print(t("tf_init_fail", err=mt5.last_error()))
            return False

        if not validate_symbol(symbol):
            return False

        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            print(t("tf_tick_fail", sym=symbol))
            return False

        stop_loss_pips = 50
        lot_size = calculate_safe_lot_size(symbol, risk_amount, stop_loss_pips)

        if order_type.upper() == "BUY":
            price = tick.ask
            stop_loss = price - (stop_loss_pips * 0.0001)
            take_profit = price + (stop_loss_pips * 2 * 0.0001)
            mt5_order_type = mt5.ORDER_TYPE_BUY
        else:
            price = tick.bid
            stop_loss = price + (stop_loss_pips * 0.0001)
            take_profit = price - (stop_loss_pips * 2 * 0.0001)
            mt5_order_type = mt5.ORDER_TYPE_SELL

        if symbol.endswith('JPY'):
            stop_loss_pips_adj = stop_loss_pips * 100
            if order_type.upper() == "BUY":
                stop_loss = price - (stop_loss_pips_adj * 0.01)
                take_profit = price + (stop_loss_pips_adj * 2 * 0.01)
            else:
                stop_loss = price + (stop_loss_pips_adj * 0.01)
                take_profit = price - (stop_loss_pips_adj * 2 * 0.01)

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": lot_size,
            "type": mt5_order_type,
            "price": price,
            "sl": stop_loss,
            "tp": take_profit,
            "deviation": 20,
            "magic": 234000,
            "comment": f"Test {order_type} order",
            "type_filling": mt5.ORDER_FILLING_IOC,
            "type_time": mt5.ORDER_TIME_GTC,
        }

        print(t("tf_placing", typ=order_type, sym=symbol))
        print(t("tf_volume", v=lot_size))
        print(t("tf_price", v=price))
        print(t("tf_sl", v=stop_loss))
        print(t("tf_tp", v=take_profit))
        print(t("tf_risk", v=risk_amount))

        result = mt5.order_send(request)
        error_messages = _retcode_messages()

        if result.retcode != mt5.TRADE_RETCODE_DONE:
            print(t("tf_order_fail"))
            print(t("tf_retcode", v=result.retcode))
            print(t("tf_comment", v=result.comment))

            if result.retcode in error_messages:
                print(t("tf_reason", msg=error_messages[result.retcode]))

            return False
        else:
            print(t("tf_order_ok"))
            print(t("tf_order_ticket", v=result.order))
            print(t("tf_deal_ticket", v=result.deal))
            print(t("tf_volume", v=result.volume))
            print(t("tf_price", v=result.price))
            print(t("tf_timestamp", v=datetime.fromtimestamp(result.time)))
            return True

    except Exception as e:
        print(t("tf_exception", e=e))
        return False


def main():
    """Main function for testing orders"""
    try:
        print(t("tf_script_title"))
        print("=" * 40)

        print(t("tf_testing_buy"))
        success_buy = place_test_order("EURUSD", "BUY", 25.0)

        if success_buy:
            import time
            time.sleep(2)

            print(t("tf_testing_sell"))
            place_test_order("GBPUSD", "SELL", 25.0)

        print("\n" + "=" * 40)
        print(t("tf_done"))

    except KeyboardInterrupt:
        print(t("tf_cancelled"))
    except Exception as e:
        print(t("tf_unexpected", e=e))
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    main()
