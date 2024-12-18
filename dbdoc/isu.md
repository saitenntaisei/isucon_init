# isu

## Description

<details>
<summary><strong>Table Definition</strong></summary>

```sql
CREATE TABLE `isu` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `jia_isu_uuid` char(36) NOT NULL,
  `name` varchar(255) NOT NULL,
  `image` longblob DEFAULT NULL,
  `character` varchar(255) DEFAULT NULL,
  `jia_user_id` varchar(255) NOT NULL,
  `created_at` datetime(6) DEFAULT current_timestamp(6),
  `updated_at` datetime(6) DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `jia_isu_uuid` (`jia_isu_uuid`)
) ENGINE=InnoDB AUTO_INCREMENT=[Redacted by tbls] DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
```

</details>

## Columns

| Name | Type | Default | Nullable | Extra Definition | Children | Parents | Comment |
| ---- | ---- | ------- | -------- | ---------------- | -------- | ------- | ------- |
| id | bigint(20) |  | false | auto_increment |  |  |  |
| jia_isu_uuid | char(36) |  | false |  |  |  |  |
| name | varchar(255) |  | false |  |  |  |  |
| image | longblob | NULL | true |  |  |  |  |
| character | varchar(255) | NULL | true |  |  |  |  |
| jia_user_id | varchar(255) |  | false |  |  |  |  |
| created_at | datetime(6) | current_timestamp(6) | true |  |  |  |  |
| updated_at | datetime(6) | current_timestamp(6) | true | on update current_timestamp(6) |  |  |  |

## Constraints

| Name | Type | Definition |
| ---- | ---- | ---------- |
| jia_isu_uuid | UNIQUE | UNIQUE KEY jia_isu_uuid (jia_isu_uuid) |
| PRIMARY | PRIMARY KEY | PRIMARY KEY (id) |

## Indexes

| Name | Definition |
| ---- | ---------- |
| PRIMARY | PRIMARY KEY (id) USING BTREE |
| jia_isu_uuid | UNIQUE KEY jia_isu_uuid (jia_isu_uuid) USING BTREE |

## Relations

![er](isu.svg)

---

> Generated by [tbls](https://github.com/k1LoW/tbls)
