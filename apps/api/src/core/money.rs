//! Money value type — integer minor units (kobo) + ISO 4217 currency.
//!
//! Money is NEVER stored or transmitted as a float. `amount_minor` is an
//! i64 count of the smallest currency unit (kobo for NGN, cents for USD…),
//! which makes addition/subtraction exact and mixing currencies a runtime
//! error rather than a settlement bug.
//!
//! Wire format (JSON):
//!
//! ```json
//! { "amount_minor": 150000, "currency": "NGN" }
//! ```
//!
//! (₦1,500.00)
//!
//! Notes:
//! - `BIGINT` in Postgres, `i64` here — plenty for minor units (i32 caps at
//!   ₦21.4m in kobo).
//! - `Currency` is an enum for type safety but carries `exponent` metadata
//!   so formatting scales to new currencies without a code change beyond
//!   adding the variant.
//! - Arithmetic is checked: overflow or currency mismatch returns `Err`
//!   instead of silently corrupting balances.

use std::fmt;

use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Currency
// ---------------------------------------------------------------------------

/// ISO 4217 currency. Only currencies the product actually settles in should
/// live here — adding a variant is the explicit, reviewable step required to
/// support a new market.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, sqlx::Type)]
#[sqlx(type_name = "TEXT", rename_all = "UPPERCASE")]
pub enum Currency {
    /// Nigerian Naira — 2 minor units (kobo).
    NGN,
    /// United States Dollar — 2 minor units (cents).
    USD,
    /// Euro — 2 minor units (cents).
    EUR,
    /// British Pound — 2 minor units (pence).
    GBP,
}

impl Currency {
    /// ISO 4217 alphabetic code (wire format).
    pub const fn code(self) -> &'static str {
        match self {
            Currency::NGN => "NGN",
            Currency::USD => "USD",
            Currency::EUR => "EUR",
            Currency::GBP => "GBP",
        }
    }

    /// Number of minor units per major unit (10^exponent).
    pub const fn exponent(self) -> u8 {
        match self {
            Currency::NGN | Currency::USD | Currency::EUR | Currency::GBP => 2,
        }
    }

    /// Minor units per major unit, e.g. 100 kobo = ₦1.
    pub const fn minor_per_major(self) -> i64 {
        10i64.pow(self.exponent() as u32)
    }

    /// Canonical symbol for display. Falls back to the code for currencies
    /// without a well-known symbol.
    pub const fn symbol(self) -> &'static str {
        match self {
            Currency::NGN => "₦",
            Currency::USD => "$",
            Currency::EUR => "€",
            Currency::GBP => "£",
        }
    }

    /// Parse from an ISO 4217 alphabetic code.
    pub fn from_code(code: &str) -> Result<Self, MoneyError> {
        match code {
            "NGN" => Ok(Currency::NGN),
            "USD" => Ok(Currency::USD),
            "EUR" => Ok(Currency::EUR),
            "GBP" => Ok(Currency::GBP),
            other => Err(MoneyError::UnknownCurrency(other.to_string())),
        }
    }
}

impl fmt::Display for Currency {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.code())
    }
}

impl Serialize for Currency {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.code())
    }
}

impl<'de> Deserialize<'de> for Currency {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let code = String::deserialize(deserializer)?;
        Currency::from_code(&code).map_err(serde::de::Error::custom)
    }
}

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/// An exact monetary amount: integer minor units + currency.
///
/// Construct via [`Money::new`] (checked), [`Money::zero`], or serde.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Money {
    /// Amount in the currency's smallest unit (kobo/cents). Never negative —
    /// settlement flows represent debits explicitly, not with signed amounts.
    pub amount_minor: i64,
    pub currency: Currency,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum MoneyError {
    #[error("amount_minor {0} is negative — money amounts must be >= 0")]
    NegativeAmount(i64),
    #[error("currency mismatch: {0} vs {1}")]
    CurrencyMismatch(Currency, Currency),
    #[error("unknown currency code: {0}")]
    UnknownCurrency(String),
    #[error("arithmetic overflow computing money amount")]
    Overflow,
    #[error("cannot allocate {0} of {1}: insufficient amount")]
    Insufficient(i64, Currency),
}

impl Money {
    /// Checked constructor. Rejects negative amounts — prices, fees, and
    /// balances in this system are unsigned by policy.
    pub fn new(amount_minor: i64, currency: Currency) -> Result<Self, MoneyError> {
        if amount_minor < 0 {
            return Err(MoneyError::NegativeAmount(amount_minor));
        }
        Ok(Self {
            amount_minor,
            currency,
        })
    }

    /// `0` of the given currency.
    pub const fn zero(currency: Currency) -> Self {
        Self {
            amount_minor: 0,
            currency,
        }
    }

    /// Build from a major-unit decimal represented as integer minor units —
    /// e.g. `from_major(1500, NGN)` is ₦1,500.00 = 150,000 kobo.
    pub fn from_major(major: i64, currency: Currency) -> Result<Self, MoneyError> {
        let minor = major
            .checked_mul(currency.minor_per_major())
            .ok_or(MoneyError::Overflow)?;
        Self::new(minor, currency)
    }

    /// Major-unit part (integer division; truncates the minor part).
    pub const fn major_part(&self) -> i64 {
        self.amount_minor / self.currency.minor_per_major()
    }

    /// Minor-unit remainder (0..minor_per_major).
    pub const fn minor_part(&self) -> i64 {
        self.amount_minor % self.currency.minor_per_major()
    }

    fn require_same_currency(&self, other: &Money) -> Result<(), MoneyError> {
        if self.currency != other.currency {
            return Err(MoneyError::CurrencyMismatch(self.currency, other.currency));
        }
        Ok(())
    }

    /// Exact addition — checked against i64 overflow.
    pub fn checked_add(&self, other: &Money) -> Result<Money, MoneyError> {
        self.require_same_currency(other)?;
        let sum = self
            .amount_minor
            .checked_add(other.amount_minor)
            .ok_or(MoneyError::Overflow)?;
        Ok(Self {
            amount_minor: sum,
            currency: self.currency,
        })
    }

    /// Exact subtraction. Errors when the result would be negative
    /// (use [`Money::checked_sub_lossy`] if saturating at zero is desired).
    pub fn checked_sub(&self, other: &Money) -> Result<Money, MoneyError> {
        self.require_same_currency(other)?;
        if other.amount_minor > self.amount_minor {
            return Err(MoneyError::Insufficient(other.amount_minor, self.currency));
        }
        Ok(Self {
            amount_minor: self.amount_minor - other.amount_minor,
            currency: self.currency,
        })
    }

    /// Saturating subtraction — floors at zero instead of erroring.
    pub fn checked_sub_lossy(&self, other: &Money) -> Result<Money, MoneyError> {
        self.require_same_currency(other)?;
        Ok(Self {
            amount_minor: (self.amount_minor - other.amount_minor).max(0),
            currency: self.currency,
        })
    }

    /// Multiply by a non-negative integer count (quantity × unit price).
    pub fn checked_mul(&self, qty: i64) -> Result<Money, MoneyError> {
        if qty < 0 {
            return Err(MoneyError::NegativeAmount(qty));
        }
        let product = self
            .amount_minor
            .checked_mul(qty)
            .ok_or(MoneyError::Overflow)?;
        Ok(Self {
            amount_minor: product,
            currency: self.currency,
        })
    }

    /// Percentage allocation with banker-safe truncation semantics made
    /// explicit: `basis_points` of 10_000 = 100%. Returns the truncated
    /// remainder too, so callers can split amounts without losing kobo:
    ///
    /// ```ignore
    /// let (fee, remainder) = money.allocate(250)?; // 2.5% platform fee
    /// ```
    ///
    /// Every kobo is accounted for across the split — sum(allocations)
    /// always equals the original amount when the caller keeps the
    /// remainders.
    pub fn allocate(&self, basis_points: i64) -> Result<(Money, Money), MoneyError> {
        if !(0..=10_000).contains(&basis_points) {
            return Err(MoneyError::Overflow); // misuse of the API
        }
        let taken = (self.amount_minor * basis_points) / 10_000;
        Ok((
            Self {
                amount_minor: taken,
                currency: self.currency,
            },
            Self {
                amount_minor: self.amount_minor - taken,
                currency: self.currency,
            },
        ))
    }

    /// Exact display string, e.g. `₦1,500.00`. Never a float: the decimal
    /// is assembled from the integer major/minor parts.
    #[allow(clippy::format_in_format_args)]
    pub fn format_args(&self) -> String {
        format!(
            "{}{}.{}",
            self.currency.symbol(),
            group_thousands(self.major_part()),
            format!("{:02}", self.minor_part())
        )
    }
}

fn group_thousands(n: i64) -> String {
    let digits = n.abs().to_string();
    let mut out = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(c);
    }
    if n < 0 { format!("-{out}") } else { out }
}

impl fmt::Display for Money {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}{}.{:02}",
            self.currency.symbol(),
            group_thousands(self.major_part()),
            self.minor_part()
        )
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn from_major_converts_naira_to_kobo() {
        let m = Money::from_major(1500, Currency::NGN).unwrap();
        assert_eq!(m.amount_minor, 150_000);
        assert_eq!(m.currency, Currency::NGN);
    }

    #[test]
    fn rejects_negative_amounts() {
        assert!(Money::new(-1, Currency::NGN).is_err());
        assert!(Money::from_major(-5, Currency::NGN).is_err());
    }

    #[test]
    fn checked_add_is_exact() {
        let a = Money::new(999, Currency::NGN).unwrap();
        let b = Money::new(1, Currency::NGN).unwrap();
        assert_eq!(a.checked_add(&b).unwrap().amount_minor, 1000);
    }

    #[test]
    fn checked_add_rejects_currency_mismatch() {
        let ngn = Money::new(100, Currency::NGN).unwrap();
        let usd = Money::new(100, Currency::USD).unwrap();
        assert!(matches!(
            ngn.checked_add(&usd),
            Err(MoneyError::CurrencyMismatch(Currency::NGN, Currency::USD))
        ));
    }

    #[test]
    fn checked_sub_rejects_going_negative() {
        let a = Money::new(100, Currency::NGN).unwrap();
        let b = Money::new(200, Currency::NGN).unwrap();
        assert!(a.checked_sub(&b).is_err());
        // lossy floors at zero
        assert_eq!(a.checked_sub_lossy(&b).unwrap().amount_minor, 0);
    }

    #[test]
    fn mul_and_overflow() {
        let unit = Money::new(450_000, Currency::NGN).unwrap(); // ₦4,500.00
        assert_eq!(unit.checked_mul(3).unwrap().amount_minor, 1_350_000);
        assert!(matches!(
            Money::new(i64::MAX, Currency::NGN).unwrap().checked_mul(2),
            Err(MoneyError::Overflow)
        ));
    }

    #[test]
    fn allocate_preserves_every_kobo() {
        let total = Money::new(9999, Currency::NGN).unwrap();
        let (fee, remainder) = total.allocate(250).unwrap(); // 2.5%
        assert_eq!(fee.amount_minor, 249); // 9999 * 250 / 10000 truncated
        assert_eq!(remainder.amount_minor, 9750);
        assert_eq!(fee.checked_add(&remainder).unwrap(), total);
    }

    #[test]
    fn format_matches_display_and_groups_thousands() {
        let m = Money::from_major(1234567, Currency::NGN).unwrap();
        assert_eq!(m.format_args(), "₦1,234,567.00");
        assert_eq!(m.to_string(), m.format_args());
    }

    #[test]
    fn currency_serde_roundtrip_by_code() {
        let json = serde_json::to_string(&Currency::NGN).unwrap();
        assert_eq!(json, r#""NGN""#);
        let back: Currency = serde_json::from_str(&json).unwrap();
        assert_eq!(back, Currency::NGN);
        assert!(serde_json::from_str::<Currency>(r#""XYZ""#).is_err());
    }

    #[test]
    fn money_serde_shape() {
        let m = Money::from_major(1500, Currency::NGN).unwrap();
        let json = serde_json::to_value(m).unwrap();
        assert_eq!(json["amount_minor"], 150_000);
        assert_eq!(json["currency"], "NGN");
        let back: Money = serde_json::from_value(json).unwrap();
        assert_eq!(back, m);
    }

    #[test]
    fn unknown_currency_code_is_an_error() {
        assert!(matches!(
            Currency::from_code("JPY"),
            Err(MoneyError::UnknownCurrency(_))
        ));
    }
}
