import Foundation

/// A real Sandbox `/transactions/sync` page, wrapped in the per-Item envelope
/// `plaid-sync` returns, with optional fields present on some rows and absent
/// on others on purpose: `txn_coffee` carries a merchant entity and the other
/// three do not, `acc_card` reports a credit limit and `acc_checking` does not,
/// and `acc_checking` reports an available balance while `acc_card` does not.
/// Uniform presence would let a decoder that mishandles absence pass. Held as
/// a literal rather than a bundled resource so the test target needs no
/// resource configuration.
///
/// Note the amounts: Plaid is positive for money leaving the account. The
/// payroll deposit is negative here and must come out of the mapper positive.
enum PlaidFixtures {
    static let syncPage = #"""
    {
      "items": [
        {
          "item_id": "item_sandbox_1",
          "institution_name": "First Platypus Bank",
          "next_cursor": "cursor_page_2",
          "has_more": false,
          "error": null,
          "accounts": [
            {
              "account_id": "acc_checking",
              "name": "Plaid Checking",
              "type": "depository",
              "subtype": "checking",
              "mask": "0000",
              "balances": {
                "current": 2450.75,
                "available": 2100.50,
                "iso_currency_code": "USD"
              }
            },
            {
              "account_id": "acc_card",
              "name": "Plaid Credit Card",
              "type": "credit",
              "subtype": "credit card",
              "mask": "4127",
              "balances": {
                "current": 610.25,
                "limit": 2000.00,
                "iso_currency_code": "USD"
              }
            }
          ],
          "added": [
            {
              "transaction_id": "txn_payroll",
              "account_id": "acc_checking",
              "amount": -3200.00,
              "iso_currency_code": "USD",
              "date": "2026-08-14",
              "name": "ACME PAYROLL DIRECT DEP",
              "merchant_name": null,
              "pending": false,
              "personal_finance_category": {
                "primary": "INCOME",
                "detailed": "INCOME_WAGES"
              }
            },
            {
              "transaction_id": "txn_coffee",
              "account_id": "acc_card",
              "amount": 6.75,
              "iso_currency_code": "USD",
              "date": "2026-08-20",
              "name": "SQ *BLUE BOTTLE",
              "merchant_name": "Blue Bottle Coffee",
              "merchant_entity_id": "mch_bluebottle",
              "logo_url": "https://plaid-merchant-logos.plaid.com/blue_bottle_1234.png",
              "pending": true,
              "personal_finance_category": {
                "primary": "FOOD_AND_DRINK",
                "detailed": "FOOD_AND_DRINK_COFFEE"
              }
            },
            {
              "transaction_id": "txn_card_payment",
              "account_id": "acc_checking",
              "amount": 400.00,
              "iso_currency_code": "USD",
              "date": "2026-08-21",
              "name": "PAYMENT THANK YOU",
              "merchant_name": null,
              "pending": false,
              "personal_finance_category": {
                "primary": "LOAN_PAYMENTS",
                "detailed": "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"
              }
            },
            {
              "transaction_id": "txn_uncategorised",
              "account_id": "acc_checking",
              "amount": 12.00,
              "iso_currency_code": null,
              "date": "2026-08-22",
              "name": "UNKNOWN VENDOR",
              "merchant_name": null,
              "pending": false,
              "personal_finance_category": null
            }
          ],
          "modified": [],
          "removed": [ { "transaction_id": "txn_stale_pending" } ]
        }
      ]
    }
    """#
}
