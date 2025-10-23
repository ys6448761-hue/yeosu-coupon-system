// /src/utils/qrCode.js
const QRCode = require('qrcode');
const crypto = require('crypto');

/**
 * 쿠폰 코드 생성 (ABC123XYZ 형식)
 * @returns {string} 9자리 랜덤 쿠폰 코드
 */
function generateCouponCode() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let code = '';
  for (let i = 0; i < 9; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

/**
 * QR 코드 데이터 생성
 * @param {string} couponCode - 쿠폰 코드
 * @returns {Promise<string>} QR 코드 Data URL
 */
async function generateQRCode(couponCode) {
  try {
    const qrCodeUrl = await QRCode.toDataURL(couponCode);
    return qrCodeUrl;
  } catch (error) {
    console.error('QR 생성 오류:', error);
    throw error;
  }
}

/**
 * QR 데이터 암호화
 * @param {string} couponCode - 쿠폰 코드
 * @returns {string} 암호화된 데이터
 */
function encryptQRData(couponCode) {
  const key = process.env.ENCRYPTION_KEY || 'secret-key-12345678901234567890123';
  const algorithm = 'aes-256-cbc';

  // 키를 32바이트로 맞춤
  const keyBuffer = Buffer.from(key.padEnd(32, '0').substring(0, 32));
  const iv = crypto.randomBytes(16);

  const cipher = crypto.createCipheriv(algorithm, keyBuffer, iv);
  let encrypted = cipher.update(couponCode, 'utf8', 'hex');
  encrypted += cipher.final('hex');

  // IV와 암호화된 데이터를 함께 반환
  return iv.toString('hex') + ':' + encrypted;
}

/**
 * QR 데이터 복호화
 * @param {string} encryptedData - 암호화된 데이터
 * @returns {string} 원본 쿠폰 코드
 */
function decryptQRData(encryptedData) {
  try {
    const key = process.env.ENCRYPTION_KEY || 'secret-key-12345678901234567890123';
    const algorithm = 'aes-256-cbc';

    // 키를 32바이트로 맞춤
    const keyBuffer = Buffer.from(key.padEnd(32, '0').substring(0, 32));

    // IV와 암호화된 데이터 분리
    const parts = encryptedData.split(':');
    const iv = Buffer.from(parts[0], 'hex');
    const encrypted = parts[1];

    const decipher = crypto.createDecipheriv(algorithm, keyBuffer, iv);
    let decrypted = decipher.update(encrypted, 'hex', 'utf8');
    decrypted += decipher.final('utf8');

    return decrypted;
  } catch (error) {
    console.error('복호화 오류:', error);
    throw error;
  }
}

module.exports = {
  generateCouponCode,
  generateQRCode,
  encryptQRData,
  decryptQRData
};
