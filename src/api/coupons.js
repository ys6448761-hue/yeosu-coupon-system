// /src/api/coupons.js
const express = require('express');
const router = express.Router();
const { Pool } = require('pg');
const { generateCouponCode, generateQRCode } = require('../utils/qrCode');

// PostgreSQL 연결
const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

// 1️⃣ POST /api/coupons/issue - 쿠폰 발급
router.post('/issue', async (req, res) => {
  const client = await pool.connect();

  try {
    const { reservation_id, customer_id, payment_key } = req.body;

    // 입력값 검증
    if (!reservation_id || !payment_key) {
      return res.status(400).json({
        success: false,
        error: 'invalid_input',
        message: '필수 필드가 누락되었습니다'
      });
    }

    // 1. 예약 정보 조회
    const reservationResult = await client.query(
      'SELECT * FROM reservations WHERE id = $1',
      [reservation_id]
    );

    if (reservationResult.rows.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'reservation_not_found',
        message: '예약을 찾을 수 없습니다'
      });
    }

    const reservation = reservationResult.rows[0];

    // 2. 결제 상태 확인
    if (reservation.payment_status !== 'completed') {
      return res.status(401).json({
        success: false,
        error: 'payment_not_completed',
        message: '결제가 완료되지 않았습니다'
      });
    }

    // 3. 레저 상품 조회 (임시: 예약에 연결된 모든 상품)
    // 실제로는 reservation_products 같은 중간 테이블 필요
    const productsResult = await client.query(
      'SELECT * FROM leisure_products WHERE partner_id IS NOT NULL LIMIT 3'
    );

    if (productsResult.rows.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'no_products',
        message: '레저 상품을 찾을 수 없습니다'
      });
    }

    // 4. 쿠폰 생성 (인원수만큼)
    const issuedCoupons = [];

    for (const product of productsResult.rows) {
      for (let i = 0; i < reservation.num_people; i++) {
        const couponCode = generateCouponCode();
        const qrCode = await generateQRCode(couponCode);

        const couponResult = await client.query(
          `INSERT INTO coupons (
            coupon_code, reservation_id, customer_id,
            leisure_product_id, partner_id, qr_data,
            customer_name, customer_phone, status,
            valid_from, valid_until
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
          RETURNING *`,
          [
            couponCode,
            reservation_id,
            customer_id || null,
            product.id,
            product.partner_id,
            qrCode,
            reservation.customer_name || '고객',
            reservation.customer_phone || '',
            'issued',
            reservation.check_in_date,
            reservation.check_out_date
          ]
        );

        const coupon = couponResult.rows[0];
        issuedCoupons.push(coupon);

        // 5. 사용 로그 기록
        await client.query(
          `INSERT INTO coupon_usage_logs (
            coupon_id, action, partner_id, partner_name
          ) VALUES ($1, $2, $3, $4)`,
          [coupon.id, 'issued', product.partner_id, product.name]
        );
      }
    }

    return res.status(200).json({
      success: true,
      issued_coupons: issuedCoupons.map(c => ({
        id: c.id,
        coupon_code: c.coupon_code,
        status: c.status,
        qr_code_url: c.qr_data,
        valid_from: c.valid_from,
        valid_until: c.valid_until
      })),
      message: `쿠폰 ${issuedCoupons.length}개가 발급되었습니다`
    });

  } catch (error) {
    console.error('쿠폰 발급 오류:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message
    });
  } finally {
    client.release();
  }
});

// 2️⃣ GET /api/coupons/:code - 쿠폰 조회 (QR 스캔)
router.get('/:code', async (req, res) => {
  const client = await pool.connect();

  try {
    const { code } = req.params;
    const { partner_id } = req.query;

    // 1. 쿠폰 조회
    const couponResult = await client.query(
      'SELECT * FROM coupons WHERE coupon_code = $1',
      [code]
    );

    if (couponResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'coupon_not_found',
        message: '쿠폰을 찾을 수 없습니다'
      });
    }

    const coupon = couponResult.rows[0];

    // 2. 파트너사 일치 확인
    if (partner_id && coupon.partner_id !== partner_id) {
      return res.status(403).json({
        success: false,
        error: 'partner_mismatch',
        message: '이 쿠폰은 다른 파트너사 쿠폰입니다'
      });
    }

    // 3. 상태 검증
    if (coupon.status === 'used') {
      return res.status(409).json({
        success: false,
        error: 'coupon_already_used',
        message: '이미 사용된 쿠폰입니다',
        used_at: coupon.used_at,
        statusCode: 409
      });
    }

    if (coupon.status === 'cancelled') {
      return res.status(409).json({
        success: false,
        error: 'coupon_cancelled',
        message: '취소된 쿠폰입니다',
        statusCode: 409
      });
    }

    // 4. 유효기간 확인
    const today = new Date();
    if (today > new Date(coupon.valid_until)) {
      // 자동 만료 처리
      await client.query(
        'UPDATE coupons SET status = $1 WHERE id = $2',
        ['expired', coupon.id]
      );

      return res.status(410).json({
        success: false,
        error: 'coupon_expired',
        message: '유효기간이 지난 쿠폰입니다',
        valid_until: coupon.valid_until,
        statusCode: 410
      });
    }

    // 5. 상태 업데이트 (issued → in_use)
    await client.query(
      'UPDATE coupons SET status = $1 WHERE id = $2',
      ['in_use', coupon.id]
    );

    return res.status(200).json({
      success: true,
      coupon: {
        id: coupon.id,
        coupon_code: coupon.coupon_code,
        customer_name: coupon.customer_name,
        customer_phone: coupon.customer_phone,
        status: 'in_use',
        valid_from: coupon.valid_from,
        valid_until: coupon.valid_until,
        message: '사용 가능한 쿠폰입니다'
      }
    });

  } catch (error) {
    console.error('쿠폰 조회 오류:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message
    });
  } finally {
    client.release();
  }
});

// 3️⃣ POST /api/coupons/:code/use - 쿠폰 사용 처리
router.post('/:code/use', async (req, res) => {
  const client = await pool.connect();

  try {
    const { code } = req.params;
    const { partner_id, staff_id, staff_name } = req.body;

    // 입력값 검증
    if (!partner_id || !staff_name) {
      return res.status(400).json({
        success: false,
        error: 'invalid_input',
        message: '필수 필드가 누락되었습니다'
      });
    }

    // 1. 쿠폰 조회
    const couponResult = await client.query(
      'SELECT * FROM coupons WHERE coupon_code = $1',
      [code]
    );

    if (couponResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'coupon_not_found',
        message: '쿠폰을 찾을 수 없습니다'
      });
    }

    const coupon = couponResult.rows[0];

    // 2. 이미 사용된 쿠폰 확인
    if (coupon.status === 'used') {
      return res.status(409).json({
        success: false,
        error: 'coupon_already_used',
        message: '이미 사용된 쿠폰입니다'
      });
    }

    // 3. 쿠폰 상태 업데이트 (used)
    const usedAt = new Date();
    const updateResult = await client.query(
      `UPDATE coupons
       SET status = $1, used_at = $2, used_by_partner_id = $3, used_by_staff_name = $4
       WHERE id = $5
       RETURNING *`,
      ['used', usedAt, partner_id, staff_name, coupon.id]
    );

    const updatedCoupon = updateResult.rows[0];

    // 4. 사용 로그 기록
    await client.query(
      `INSERT INTO coupon_usage_logs (
        coupon_id, action, partner_id, staff_name
      ) VALUES ($1, $2, $3, $4)`,
      [coupon.id, 'used', partner_id, staff_name]
    );

    return res.status(200).json({
      success: true,
      coupon: {
        coupon_code: updatedCoupon.coupon_code,
        status: updatedCoupon.status,
        used_at: usedAt,
        used_by_staff: staff_name,
        message: '입장 처리가 완료되었습니다'
      }
    });

  } catch (error) {
    console.error('쿠폰 사용 오류:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message
    });
  } finally {
    client.release();
  }
});

module.exports = router;
