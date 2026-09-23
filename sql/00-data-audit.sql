-- 00-data-audit.sql — знакомство с данными: проверки до анализа
-- Каждая проверка: Q (вопрос) → запрос → A (найдено)

-- ===== categories =====

-- Q: что вообще лежит в таблице?
SELECT * FROM marketplace.categories LIMIT 10;
-- A: идентификатор категории, имена — случайные слова, встречается строка 'None', 
-- идентификатор родительской категории.

-- Q: Сколько строк с ловушками None?
SELECT * FROM marketplace.categories WHERE name = 'None';
-- A: 2 строки.

-- Q: сколько строк в таблице?
SELECT count(*) FROM marketplace.categories;
-- A: в таблице 1800 строк.

-- Q: сколько уникальных названий категорий?
SELECT count(DISTINCT name) FROM marketplace.categories; 
-- A: 826 уникальных названий категорий.

-- Q: сколько уникальных идентификаторов категорий?
SELECT count(DISTINCT category_id) FROM marketplace.categories; 
-- A: 1800 уникальных category_id, совпадает с количеством строк.

-- Q: целостна ли иерархия (все родители существуют)?
SELECT count(*) FROM marketplace.categories c
LEFT JOIN marketplace.categories p ON c.parent_category_id = p.category_id
WHERE c.parent_category_id IS NOT NULL AND p.category_id IS NULL;
-- A: 0 сирот — иерархия целостна.

-- Q: сколько корневых категорий?
SELECT count(*) FROM marketplace.categories WHERE parent_category_id IS NULL; 
-- A: 885 корневых категорий.


-- ===== orders =====

-- Q: что вообще лежит в таблице?
SELECT * FROM marketplace.orders LIMIT 10;
-- A: идентификатор заказов, покупателей, дата и время оформления заказа, 
-- актуальный статус, сумма заказа.

-- Q: сколько строк в таблице?
SELECT count(*) FROM marketplace.orders;
-- A: в таблице 505400 строки.

-- Q: сколько уникальных заказов?
SELECT count(DISTINCT order_id) FROM marketplace.orders;
-- A: количество уникальных заказов совпадает с количеством строк -
-- 505400 заказов.

-- Q: сколько уникальных покупателей?
SELECT count(DISTINCT buyer_id) FROM marketplace.orders;
-- A: уникальных покупателей 55652.

-- Q: присутствуют ли пустые значения?
SELECT * FROM marketplace.orders 
WHERE buyer_id IS NULL OR order_date IS NULL OR status IS NULL OR total_amount IS null;
-- A: пустые значения отсутствуют.

-- Q: за какой период выгружены данные?
SELECT min(order_date), max(order_date) FROM marketplace.orders;
-- A: данные выгружены за период 2023-06-10 - 2025-06-09.

-- Q: какие статусы заказа бывают и их распределение?
SELECT status, count(*) FROM marketplace.orders GROUP BY status;
-- A: примерно равное распределение заказов по 4 статусам по 125 тыс строк.
-- статусы: new, paid, shipped, canceled.

-- Q: какое распределение суммы заказа?
SELECT min(total_amount), round(avg(total_amount)), max(total_amount) FROM marketplace.orders;
-- A: от 10 до 12700 условных единиц, среднее 3038 у.е.

-- Q: как заказы распределяются по времени
WITH orders_per_month AS (
SELECT order_id, date_trunc('MONTH', order_date) AS yy_mm FROM marketplace.orders)
SELECT yy_mm, count (order_id) FROM orders_per_month GROUP BY yy_mm ORDER BY yy_mm;
-- A: количество заказов от месяца к месяцу растет.

-- ===== order_items =====

-- Q: что вообще лежит в таблице?
SELECT * FROM marketplace.order_items LIMIT 10;
-- A: идентификатор заказов, идентификатор позиции заказа, идентификатор товара, 
-- количество и цена на момент продажи.

-- Q: сколько строк в таблице?
SELECT count(*) FROM marketplace.order_items;
-- A: в таблице 1516751 строки.

-- Q: сколько уникальных заказов?
SELECT count(DISTINCT order_id) FROM marketplace.order_items;
-- A: количество уникальных заказов совпадает с количеством строк из таблицы orders -
-- 505400 уникальных заказов.

-- Q: заказы совпадают в табличках orders и order_items?
SELECT 'нет позиций' as problem, o.order_id
FROM marketplace.orders o
WHERE NOT EXISTS (
  SELECT 1 FROM marketplace.order_items oi WHERE oi.order_id = o.order_id
)

UNION ALL

SELECT 'нет шапки' as problem, oi.order_id
FROM (SELECT DISTINCT order_id FROM marketplace.order_items) oi
WHERE NOT EXISTS (
  SELECT 1 FROM marketplace.orders o WHERE o.order_id = oi.order_id
);
-- A: да, заказы совпадают, проблемных нет.

-- Q: сколько уникальных товаров было продано?
SELECT count(DISTINCT product_id) FROM marketplace.order_items;
-- A: было продано 52100 уникальных товаров.

-- Q: присутствуют ли пустые значения?
SELECT * FROM marketplace.order_items 
WHERE product_id IS NULL OR order_id IS NULL OR 
      quantity IS NULL OR price_at_order_time IS null;
-- A: пустые значения отсутствуют.

-- Q: совпадают ли суммы заказов?
WITH oi_amount AS (
  SELECT order_id,
         round(sum(quantity::numeric * price_at_order_time::numeric), 2) AS oi_total_amount
  FROM marketplace.order_items
  GROUP BY order_id
),
diffs AS (
  SELECT
    o.order_id,
    round(o.total_amount::numeric, 2) AS total_amount,
    a.oi_total_amount,
    round(o.total_amount::numeric, 2) - a.oi_total_amount AS diff
  FROM marketplace.orders o
  JOIN oi_amount a ON a.order_id = o.order_id
  WHERE round(o.total_amount::numeric, 2) <> a.oi_total_amount
)
SELECT
  count(*)                AS orders_with_diff,
  min(diff)               AS min_diff,
  max(diff)               AS max_diff,
  avg(diff)               AS avg_diff
FROM diffs;
-- A: суммы заказов совпадают.
-- Расхождения вызваны разницей в порядке округления при расчёте сумм:
-- orders.total_amount, вероятно, рассчитывался с округлением на другом этапе,
-- чем сумма позиций в order_items.
-- Остаточная разница ±0.05 руб. соответствует половине копейки на позицию
-- и является артефактом округления, а не ошибкой данных.


-- ===== products =====

-- Q: что вообще лежит в таблице?
SELECT * FROM marketplace.products LIMIT 10;
-- A: идентификатор, название и описание товаров, идентификатор категории, 
-- цена, но неизвестно, актуальная на какой момент, 
-- количество товара в наличии и идентификатор продавца.

-- Q: сколько строк в таблице?
SELECT count(*) FROM marketplace.products;
-- A: в таблице 52100 строки.

-- Q: сколько уникальных товаров?
SELECT count(DISTINCT product_id) FROM marketplace.products;
-- A: количество уникальных товаров совпадает с общим количеством строк в таблице -
-- 52100 товаров.

-- Q: присутствуют ли пустые значения?
SELECT * FROM marketplace.products 
WHERE title IS NULL OR description IS NULL OR category_id IS NULL OR 
      price IS NULL OR seller_id IS NULL OR stock_quantity IS null;
-- A: пустые значения отсутствуют.

-- Q: сколько уникальных продавцов?
SELECT count(DISTINCT seller_id) FROM marketplace.products;
-- A: уникальных 33813 продацов.


-- ===== reviews =====

-- Q: что вообще лежит в таблице?
SELECT * FROM marketplace.reviews LIMIT 10;
-- A: идентификатор отзыва, идентификатор пользователя, оставивший отзыв, 
-- идентификатор товара, на который был оставлен отзыв, рейтинг, 
-- комментарий и дата оставления отзыва.

-- Q: сколько строк в таблице?
SELECT count(*) FROM marketplace.reviews;
-- A: в таблице 310100 строки.

-- Q: присутствуют ли пустые значения?
SELECT * FROM marketplace.reviews 
WHERE user_id IS NULL OR product_id IS NULL OR rating IS NULL OR 
      comment IS NULL OR COMMENT = '' OR review_date IS NULL;
-- A: пустые значения отсутствуют.

-- Q: сколько уникальных пользователей, которые оставили отзыв?
SELECT count(DISTINCT user_id) FROM marketplace.reviews;
-- A: 55441 уникальных пользователей, которые оставили отзывы.

-- Q: сколько в среднем отзывов оставляет 1 пользователь?
SELECT count(*) / count(DISTINCT user_id) FROM marketplace.reviews;
-- A: на одного пользователя приходится в среднем по 5 отзывов.

-- Q: топ-10 по количеству отзывов
SELECT product_id, count(*) FROM marketplace.reviews 
GROUP BY product_id ORDER BY count(*) DESC LIMIT 10;

-- Q: антитоп-10 по количеству отзывов
SELECT product_id, count(*) FROM marketplace.reviews 
GROUP BY product_id ORDER BY count(*) asc LIMIT 10;

-- Q: какую оценку оставляют пользователи чаще всего?
SELECT rating, count(*) FROM marketplace.reviews GROUP BY rating;
-- A: оценки от 1 до 5 распределены примерно равномерно по 61 тыс.


-- ===== transactions =====

-- Q: что вообще лежит в таблице?
SELECT * FROM marketplace.transactions LIMIT 10;
-- A: идентификатор транзакции, идентификатор пользователя, 
-- сумма транзакции, тип и дата совершения транзакции.

-- Q: сколько строк в таблице?
SELECT count(*) FROM marketplace.transactions;
-- A: в таблице 811200 строки.

-- Q: присутствуют ли пустые значения?
SELECT * FROM marketplace.transactions 
WHERE user_id IS NULL OR amount IS NULL OR 
      transaction_type IS NULL OR transaction_date IS NULL;
-- A: пустые значения отсутствуют.

-- Q: сколько уникальных пользователей совершали какую либо транзакцию?
SELECT count(DISTINCT user_id) FROM marketplace.transactions;
-- A: 111211 уникальных пользователя совершали транзакции.

-- Q: сколько в среднем операций на 1 пользователь?
SELECT count(*) / count(DISTINCT user_id) FROM marketplace.transactions;
-- A: на одного пользователя приходится по 7 операций.

-- Q: какие операции встречаются и их распределение?
SELECT transaction_type, count(*) FROM marketplace.transactions GROUP BY transaction_type;
-- A: встречаются 3 типа транзакции: payment, payout и refund.
-- Распределяются в равной степени по 270 тыс строк.

-- Q: какие суммы встречаются?
SELECT min(amount), max(amount), round(avg(amount)) FROM marketplace.transactions;
-- A: мин -500, макс 2 000, среднее 749 условных единиц.


-- ===== users =====

-- Q: что вообще лежит в таблице?
SELECT * FROM marketplace.users LIMIT 10;
-- A: идентификатор пользователя, имя, электронная почта, 
--   телефон, тип пользователя, дата регистрации и характеристика активности.

-- Q: сколько строк в таблице?
SELECT count(*) FROM marketplace.users;
-- A: в таблице 111399 строки.

-- Q: какое распределение по типам пользователя?
SELECT user_type, count(*) FROM marketplace.users GROUP BY user_type;
-- A: равное распределение по примерно 55 тысяч на buyer и seller.

-- Q: можно ли на одну почту зарегистрироваться несколько раз?
SELECT email, count(*) FROM marketplace.users 
GROUP BY email HAVING count(*) >1 ORDER BY count(*) desc;
-- A: на один email может быть до 18 регистраций.

-- Q: присутствуют ли пустые значения?
SELECT * FROM marketplace.users WHERE name IS NULL OR email IS NULL OR phone IS NULL OR user_type IS NULL OR registration_date IS NULL OR is_active IS null;
-- A: пустые значения отсутствуют.
