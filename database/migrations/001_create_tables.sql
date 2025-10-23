-- ═══════════════════════════════════════════════════════════
-- 여수여행센터 통합 쿠폰 시스템 - Database Migration
-- Phase 1: 테이블 생성
-- PostgreSQL 14+
-- ═══════════════════════════════════════════════════════════

-- UUID 확장 활성화 (PostgreSQL 13+ 는 기본 제공)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ═══════════════════════════════════════════════════════════
-- 테이블 1: customers (고객)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    gender VARCHAR(10),
    birth_date DATE,
    type VARCHAR(20) DEFAULT 'individual' CHECK (type IN ('individual', 'group', 'guest')),
    is_active BOOLEAN DEFAULT TRUE,
    signup_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 인덱스 생성
CREATE INDEX idx_customers_phone ON customers(phone);
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_type ON customers(type);

COMMENT ON TABLE customers IS '고객 정보 테이블';
COMMENT ON COLUMN customers.type IS '고객 유형: individual(개인), group(단체), guest(게스트)';

-- ═══════════════════════════════════════════════════════════
-- 테이블 2: partners (파트너사) - reservations보다 먼저 생성
-- ═══════════════════════════════════════════════════════════

CREATE TABLE partners (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL CHECK (category IN ('cable_car', 'aqua', 'yacht', 'cruise', 'hotel', 'restaurant', 'other')),
    login_id VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(100),
    contact_person VARCHAR(100),
    settlement_cycle VARCHAR(20) DEFAULT 'monthly' CHECK (settlement_cycle IN ('daily', 'weekly', 'monthly')),
    settlement_day INT,
    last_settlement_date DATE,
    bank_name VARCHAR(50),
    account_number VARCHAR(50),
    account_holder VARCHAR(100),
    commission_rate DECIMAL(5,2) DEFAULT 5.0 CHECK (commission_rate >= 0 AND commission_rate <= 100),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 인덱스 생성
CREATE INDEX idx_partners_category ON partners(category);
CREATE INDEX idx_partners_login_id ON partners(login_id);
CREATE INDEX idx_partners_is_active ON partners(is_active);

COMMENT ON TABLE partners IS '파트너사 정보 테이블';
COMMENT ON COLUMN partners.category IS '파트너사 카테고리: cable_car(케이블카), aqua(아쿠아플라넷), yacht(요트), cruise(유람선), hotel(호텔)';
COMMENT ON COLUMN partners.commission_rate IS '수수료율 (%)';

-- ═══════════════════════════════════════════════════════════
-- 테이블 3: reservations (예약)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE reservations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    reservation_number VARCHAR(50) NOT NULL UNIQUE,
    reservation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    num_people INT NOT NULL CHECK (num_people > 0),
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    original_price DECIMAL(10,2),
    sale_price DECIMAL(10,2) NOT NULL CHECK (sale_price >= 0),
    discount_amount DECIMAL(10,2) DEFAULT 0,
    payment_method VARCHAR(50),
    payment_status VARCHAR(50) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded')),
    payment_key VARCHAR(255),
    order_id VARCHAR(100) UNIQUE,
    status VARCHAR(50) DEFAULT 'confirmed' CHECK (status IN ('pending', 'confirmed', 'cancelled', 'completed')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_dates CHECK (check_out_date >= check_in_date)
);

-- 인덱스 생성
CREATE INDEX idx_reservations_reservation_number ON reservations(reservation_number);
CREATE INDEX idx_reservations_payment_status ON reservations(payment_status);
CREATE INDEX idx_reservations_customer_id ON reservations(customer_id);
CREATE INDEX idx_reservations_status ON reservations(status);
CREATE INDEX idx_reservations_check_in_date ON reservations(check_in_date);

COMMENT ON TABLE reservations IS '예약 정보 테이블';
COMMENT ON COLUMN reservations.payment_status IS '결제 상태: pending(대기), completed(완료), failed(실패), refunded(환불)';
COMMENT ON COLUMN reservations.status IS '예약 상태: pending(대기), confirmed(확정), cancelled(취소), completed(완료)';

-- ═══════════════════════════════════════════════════════════
-- 테이블 4: leisure_products (레저 상품)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE leisure_products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
    base_price DECIMAL(10,2) NOT NULL CHECK (base_price >= 0),
    discount_rate DECIMAL(5,2) DEFAULT 0 CHECK (discount_rate >= 0 AND discount_rate <= 100),
    inventory INT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 인덱스 생성
CREATE INDEX idx_leisure_products_partner_id ON leisure_products(partner_id);
CREATE INDEX idx_leisure_products_category ON leisure_products(category);
CREATE INDEX idx_leisure_products_is_active ON leisure_products(is_active);

COMMENT ON TABLE leisure_products IS '레저 상품 정보 테이블';
COMMENT ON COLUMN leisure_products.discount_rate IS '할인율 (%)';

-- ═══════════════════════════════════════════════════════════
-- 테이블 5: coupons (쿠폰 - 핵심 테이블!)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE coupons (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    coupon_code VARCHAR(20) NOT NULL UNIQUE,
    reservation_id UUID NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    leisure_product_id UUID NOT NULL REFERENCES leisure_products(id) ON DELETE CASCADE,
    partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
    qr_data VARCHAR(500),
    customer_name VARCHAR(100),
    customer_phone VARCHAR(20),
    status VARCHAR(50) DEFAULT 'issued' CHECK (status IN ('issued', 'sent', 'in_use', 'used', 'cancelled', 'expired')),
    issued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMP,
    used_at TIMESTAMP,
    used_by_partner_id UUID REFERENCES partners(id) ON DELETE SET NULL,
    used_by_staff_name VARCHAR(100),
    valid_from DATE NOT NULL,
    valid_until DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_valid_dates CHECK (valid_until >= valid_from)
);

-- 인덱스 생성
CREATE INDEX idx_coupons_coupon_code ON coupons(coupon_code);
CREATE INDEX idx_coupons_status ON coupons(status);
CREATE INDEX idx_coupons_customer_phone ON coupons(customer_phone);
CREATE INDEX idx_coupons_valid_until ON coupons(valid_until);
CREATE INDEX idx_coupons_reservation_id ON coupons(reservation_id);
CREATE INDEX idx_coupons_partner_id ON coupons(partner_id);

COMMENT ON TABLE coupons IS '쿠폰 정보 테이블 (핵심)';
COMMENT ON COLUMN coupons.coupon_code IS '쿠폰 코드 (예: ABC123XYZ)';
COMMENT ON COLUMN coupons.status IS '쿠폰 상태: issued(발급), sent(발송), in_use(사용중), used(사용완료), cancelled(취소), expired(만료)';
COMMENT ON COLUMN coupons.qr_data IS '암호화된 QR 데이터';

-- ═══════════════════════════════════════════════════════════
-- 테이블 6: coupon_usage_logs (쿠폰 사용 이력)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE coupon_usage_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    coupon_id UUID NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL CHECK (action IN ('issued', 'sent', 'verified', 'used', 'cancelled', 'expired')),
    action_description TEXT,
    partner_id UUID REFERENCES partners(id) ON DELETE SET NULL,
    partner_name VARCHAR(100),
    staff_name VARCHAR(100),
    ip_address VARCHAR(45),
    user_agent VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 인덱스 생성
CREATE INDEX idx_coupon_usage_logs_coupon_id ON coupon_usage_logs(coupon_id);
CREATE INDEX idx_coupon_usage_logs_created_at ON coupon_usage_logs(created_at);
CREATE INDEX idx_coupon_usage_logs_action ON coupon_usage_logs(action);

COMMENT ON TABLE coupon_usage_logs IS '쿠폰 사용 이력 로그 테이블';
COMMENT ON COLUMN coupon_usage_logs.action IS '액션 유형: issued(발급), sent(발송), verified(검증), used(사용), cancelled(취소), expired(만료)';

-- ═══════════════════════════════════════════════════════════
-- 테이블 7: partner_staff (파트너사 직원)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE partner_staff (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(100),
    role VARCHAR(50) DEFAULT 'staff' CHECK (role IN ('manager', 'staff', 'admin')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 인덱스 생성
CREATE INDEX idx_partner_staff_partner_id ON partner_staff(partner_id);
CREATE INDEX idx_partner_staff_is_active ON partner_staff(is_active);

COMMENT ON TABLE partner_staff IS '파트너사 직원 정보 테이블';
COMMENT ON COLUMN partner_staff.role IS '역할: manager(관리자), staff(직원), admin(최고관리자)';

-- ═══════════════════════════════════════════════════════════
-- 테이블 8: settlements (정산)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE settlements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id UUID NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
    settlement_period_start DATE NOT NULL,
    settlement_period_end DATE NOT NULL,
    total_coupons_used INT DEFAULT 0 CHECK (total_coupons_used >= 0),
    total_amount DECIMAL(15,2) DEFAULT 0 CHECK (total_amount >= 0),
    commission_amount DECIMAL(15,2) DEFAULT 0 CHECK (commission_amount >= 0),
    settlement_amount DECIMAL(15,2) DEFAULT 0 CHECK (settlement_amount >= 0),
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'paid', 'cancelled')),
    paid_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_settlement_dates CHECK (settlement_period_end >= settlement_period_start)
);

-- 인덱스 생성
CREATE INDEX idx_settlements_partner_id ON settlements(partner_id);
CREATE INDEX idx_settlements_status ON settlements(status);
CREATE INDEX idx_settlements_period ON settlements(settlement_period_start, settlement_period_end);

COMMENT ON TABLE settlements IS '정산 정보 테이블';
COMMENT ON COLUMN settlements.status IS '정산 상태: pending(대기), completed(완료), paid(지급완료), cancelled(취소)';
COMMENT ON COLUMN settlements.total_amount IS '총 금액 (수수료 제외)';
COMMENT ON COLUMN settlements.commission_amount IS '수수료 금액';
COMMENT ON COLUMN settlements.settlement_amount IS '정산 금액 (total_amount - commission_amount)';

-- ═══════════════════════════════════════════════════════════
-- 트리거 함수: updated_at 자동 업데이트
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 트리거 적용
CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_reservations_updated_at BEFORE UPDATE ON reservations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_partners_updated_at BEFORE UPDATE ON partners
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_leisure_products_updated_at BEFORE UPDATE ON leisure_products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_coupons_updated_at BEFORE UPDATE ON coupons
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_partner_staff_updated_at BEFORE UPDATE ON partner_staff
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_settlements_updated_at BEFORE UPDATE ON settlements
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ═══════════════════════════════════════════════════════════
-- 완료 메시지
-- ═══════════════════════════════════════════════════════════

DO $$
BEGIN
    RAISE NOTICE '✅ 여수여행센터 통합 쿠폰 시스템 데이터베이스 마이그레이션 완료!';
    RAISE NOTICE '📊 생성된 테이블: 8개';
    RAISE NOTICE '🔑 생성된 인덱스: 35개';
    RAISE NOTICE '⚡ 생성된 트리거: 7개';
END $$;
