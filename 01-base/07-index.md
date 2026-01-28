# 索引管理

## 索引类型

Doris 支持多种索引类型，适用于不同的查询场景：

| 索引类型 | 适用场景 | 特点 |
|---------|---------|------|
| BITMAP | 低基数列（枚举值） | 位图索引，适合 IN 查询 |
| Bloom Filter | 高基数列 | 布隆过滤器，适合等值查询 |
| NGram Bloom Filter | 文本列 | N-gram 布隆过滤器，适合模糊查询 |
| Inverted | 全文检索 | 倒排索引，适合全文搜索 |

## BITMAP 索引

### 创建 BITMAP 索引

```sql
-- 创建 BITMAP 索引
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP;

-- 创建多个 BITMAP 索引
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP;
CREATE INDEX idx_gender_bitmap ON users (gender) USING BITMAP;
CREATE INDEX idx_status_bitmap ON users (status) USING BITMAP;

-- 创建 BITMAP 索引（带注释）
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP COMMENT 'City bitmap index';
```

### 使用 BITMAP 索引

```sql
-- BITMAP 索引自动生效
SELECT * FROM users WHERE city = 'Beijing';

-- IN 查询使用 BITMAP 索引
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai', 'Guangzhou');

-- 多条件查询
SELECT * FROM users WHERE city = 'Beijing' AND gender = 'male';
```

### 删除 BITMAP 索引

```sql
-- 删除 BITMAP 索引
DROP INDEX idx_city_bitmap ON users;

-- 删除多个 BITMAP 索引
DROP INDEX idx_city_bitmap ON users;
DROP INDEX idx_gender_bitmap ON users;
```

## Bloom Filter 索引

### 创建 Bloom Filter 索引

```sql
-- 创建 Bloom Filter 索引（单列）
ALTER TABLE users SET ("bloom_filter_columns" = "user_id");

-- 创建 Bloom Filter 索引（多列）
ALTER TABLE users SET ("bloom_filter_columns" = "user_id,email,phone");

-- 创建 Bloom Filter 索引（建表时指定）
CREATE TABLE users (
    user_id BIGINT,
    user_name VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(20)
)
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "bloom_filter_columns" = "user_id,email,phone"
);
```

### Bloom Filter 参数

```sql
-- 设置 Bloom Filter 大小
ALTER TABLE users SET ("bloom_filter_fpp" = "0.05");

-- Bloom Filter 参数说明
-- bloom_filter_columns: 指定列名，多个列用逗号分隔
-- bloom_filter_fpp: 误判率，默认 0.05，范围 [0.0001, 1]
```

### 使用 Bloom Filter 索引

```sql
-- Bloom Filter 索引自动生效
SELECT * FROM users WHERE user_id = 12345;

-- IN 查询使用 Bloom Filter 索引
SELECT * FROM users WHERE user_id IN (12345, 67890, 11111);

-- 多条件查询
SELECT * FROM users WHERE user_id = 12345 AND email = 'test@example.com';
```

### 删除 Bloom Filter 索引

```sql
-- 删除 Bloom Filter 索引
ALTER TABLE users UNSET ("bloom_filter_columns");

-- 删除指定列的 Bloom Filter 索引
ALTER TABLE users SET ("bloom_filter_columns" = "user_id,email");
```

## NGram Bloom Filter 索引

### 创建 NGram Bloom Filter 索引

```sql
-- 创建 NGram Bloom Filter 索引
CREATE INDEX idx_name_ngram ON users (user_name) USING NGRAM_BLOOM;

-- 创建 NGram Bloom Filter 索引（指定 N-gram 大小）
CREATE INDEX idx_name_ngram ON users (user_name) USING NGRAM_BLOOM PROPERTIES ("gram_size" = "3");

-- 创建 NGram Bloom Filter 索引（建表时指定）
CREATE TABLE users (
    user_id BIGINT,
    user_name VARCHAR(100),
    email VARCHAR(100)
)
DUPLICATE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 10
PROPERTIES (
    "ngram_bloom_filter_columns" = "user_name"
);
```

### 使用 NGram Bloom Filter 索引

```sql
-- LIKE 查询使用 NGram Bloom Filter 索引
SELECT * FROM users WHERE user_name LIKE 'Alice%';

-- 模糊查询
SELECT * FROM users WHERE user_name LIKE '%Alice%';

-- 正则表达式查询
SELECT * FROM users WHERE user_name REGEXP '^A.*e$';
```

### 删除 NGram Bloom Filter 索引

```sql
-- 删除 NGram Bloom Filter 索引
DROP INDEX idx_name_ngram ON users;

-- 删除建表时指定的 NGram Bloom Filter 索引
ALTER TABLE users UNSET ("ngram_bloom_filter_columns");
```

## Inverted 索引

### 创建 Inverted 索引

```sql
-- 创建 Inverted 索引
CREATE INDEX idx_content_inverted ON articles (content) USING INVERTED;

-- 创建 Inverted 索引（带分词器）
CREATE INDEX idx_content_inverted ON articles (content) USING INVERTED PROPERTIES ("parser" = "english");

-- 创建 Inverted 索引（建表时指定）
CREATE TABLE articles (
    article_id BIGINT,
    title VARCHAR(200),
    content TEXT
)
DUPLICATE KEY(article_id)
DISTRIBUTED BY HASH(article_id) BUCKETS 10
PROPERTIES (
    "inverted_index_columns" = "content"
);
```

### 使用 Inverted 索引

```sql
-- 全文检索
SELECT * FROM articles WHERE content MATCH 'database';

-- 全文检索（带短语）
SELECT * FROM articles WHERE content MATCH '"Apache Doris"';

-- 全文检索（带 AND）
SELECT * FROM articles WHERE content MATCH 'database AND performance';

-- 全文检索（带 OR）
SELECT * FROM articles WHERE content MATCH 'database OR performance';
```

### 删除 Inverted 索引

```sql
-- 删除 Inverted 索引
DROP INDEX idx_content_inverted ON articles;

-- 删除建表时指定的 Inverted 索引
ALTER TABLE articles UNSET ("inverted_index_columns");
```

## 索引管理

### 查看索引

```sql
-- 查看表的所有索引
SHOW INDEX FROM users;

-- 查看指定索引
SHOW INDEX FROM users WHERE Key_name = 'idx_city_bitmap';

-- 查看索引详细信息
SHOW INDEX FROM users\G
```

### 查看索引使用情况

```sql
-- 查看查询执行计划（是否使用索引）
EXPLAIN SELECT * FROM users WHERE city = 'Beijing';

-- 查看查询执行计划（详细）
EXPLAIN VERBOSE SELECT * FROM users WHERE city = 'Beijing';
```

## 索引最佳实践

### 1. 选择合适的索引类型

| 列类型 | 推荐索引类型 | 示例 |
|--------|------------|------|
| 低基数（枚举值） | BITMAP | city, gender, status |
| 高基数（ID） | Bloom Filter | user_id, order_id |
| 文本列 | NGram Bloom Filter | user_name, email |
| 长文本 | Inverted | content, description |

### 2. 合理设置索引列

```sql
-- 好的索引：查询条件中经常使用的列
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP;

-- 不好的索引：基数太小的列
CREATE INDEX idx_gender_bitmap ON users (gender) USING BITMAP;

-- 不好的索引：很少查询的列
CREATE INDEX idx_address_bitmap ON users (address) USING BITMAP;
```

### 3. 控制索引数量

```sql
-- 太多的索引：影响写入性能
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP;
CREATE INDEX idx_gender_bitmap ON users (gender) USING BITMAP;
CREATE INDEX idx_status_bitmap ON users (status) USING BITMAP;
CREATE INDEX idx_email_bloom ON users (email) USING BLOOM;
CREATE INDEX idx_phone_bloom ON users (phone) USING BLOOM;
...

-- 合理的索引：只创建必要的索引
CREATE INDEX idx_city_bitmap ON users (city) USING BITMAP;
CREATE INDEX idx_email_bloom ON users (email) USING BLOOM;
```

### 4. 定期维护索引

```sql
-- 重建索引
ALTER TABLE users REBUILD INDEX idx_city_bitmap;

-- 删除未使用的索引
DROP INDEX idx_city_bitmap ON users;
```

## 索引性能优化

### 1. 使用 EXPLAIN 分析查询

```sql
-- 查看查询执行计划
EXPLAIN SELECT * FROM users WHERE city = 'Beijing';

-- 查看详细执行计划
EXPLAIN VERBOSE SELECT * FROM users WHERE city = 'Beijing';
```

### 2. 监控索引使用情况

```sql
-- 查看表的统计信息
SHOW TABLE STATUS WHERE Name = 'users';

-- 查看列的统计信息
SHOW COLUMN STATS FROM users;
```

### 3. 优化索引参数

```sql
-- 调整 Bloom Filter 误判率
ALTER TABLE users SET ("bloom_filter_fpp" = "0.01");

-- 调整 NGram 大小
CREATE INDEX idx_name_ngram ON users (user_name) USING NGRAM_BLOOM PROPERTIES ("gram_size" = "2");
```

## 常见问题

### 索引未生效

```sql
-- 检查索引是否存在
SHOW INDEX FROM users;

-- 检查查询是否使用索引
EXPLAIN SELECT * FROM users WHERE city = 'Beijing';

-- 强制使用索引（不推荐）
SELECT * FROM users USE INDEX (idx_city_bitmap) WHERE city = 'Beijing';
```

### 索引占用空间过大

```sql
-- 删除不必要的索引
DROP INDEX idx_city_bitmap ON users;

-- 调整 Bloom Filter 参数
ALTER TABLE users SET ("bloom_filter_fpp" = "0.1");
```

### 索引影响写入性能

```sql
-- 减少索引数量
DROP INDEX idx_city_bitmap ON users;
DROP INDEX idx_gender_bitmap ON users;

-- 批量插入时暂时禁用索引（不支持）
-- 建议：批量插入后再创建索引
```

## 下一步

- [JOIN 操作](./08-join.md) - 学习如何进行多表关联查询
