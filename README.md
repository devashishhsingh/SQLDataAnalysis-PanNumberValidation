# SQLDataAnalysis-PanNumberValidation
## 📌 Objective

The objective of this project is to **clean and validate a dataset of Permanent Account Numbers (PAN)** for Indian nationals.
The dataset is provided in an Excel file: **`PAN Number Validation Dataset.csv`**.

The project ensures that each PAN number:

* Adheres to the official PAN format.
* Is classified as **Valid** or **Invalid** based on defined rules.

---

## ⚙️ Steps Involved

### 1️⃣ Data Cleaning & Preprocessing

* **Missing Data** → Identify and handle rows where PAN numbers are `NULL` or blank.
* **Duplicates** → Detect and remove duplicate PAN entries.
* **Spaces** → Remove leading/trailing whitespaces.
* **Case Normalization** → Convert all PAN numbers to **uppercase** for consistency.

---

### 2️⃣ PAN Format Validation Rules

A valid PAN must satisfy the following:

✔️ Exactly **10 characters long**
✔️ Structure: `AAAAA1234A`

* First **5 characters**: Alphabets (A–Z)
* Next **4 characters**: Digits (0–9)
* Last **1 character**: Alphabet (A–Z)

Additional rules:

* ❌ No adjacent **same alphabets** (e.g., `AABCD` invalid)
* ❌ No sequential **alphabets** (e.g., `ABCDE`, `BCDEF` invalid)
* ❌ No adjacent **same digits** (e.g., `1123` invalid)
* ❌ No sequential **digits** (e.g., `1234`, `2345` invalid)

✅ Example of Valid PAN: `AHGVE1276F`

---

### 3️⃣ Categorisation

* **Valid PAN** → Matches all rules.
* **Invalid PAN** → Fails any rule, incomplete, or contains invalid characters.

---

### 4️⃣ Summary Report

Final output includes:

* Total records processed
* Total valid PANs
* Total invalid PANs
* Total missing/incomplete PANs

---

Awesome — here’s a **clear, query-by-query explanation** of your PostgreSQL SQL so anyone can see *what each piece does* and *why it’s used*. 
I’ve also fixed typos in object names (e.g., `vaild` → `valid`, `charcters` → `characters`, `sequencial` → `sequential`) and noted where behavior might surprise you.

---

# Query-by-Query Explanation (PostgreSQL)

## 0) Staging table

```sql
CREATE TABLE stg_pan_numbers_dataset (
  pan_number TEXT
);
```

**Why:**
A simple **staging** table to load raw values “as is”. `TEXT` is flexible and avoids premature validation during load.

---

## 1) Quick sanity check

```sql
SELECT * FROM stg_pan_numbers_dataset;
```

**Why:**
Confirms the load worked (or that it’s empty before loading).

---

## 2) Find missing data

```sql
SELECT *
FROM stg_pan_numbers_dataset
WHERE pan_number IS NULL;
```

**Why:**
Catches **true NULLs**.

> Tip: users often enter blanks, not NULLs. To also catch blanks:

```sql
SELECT *
FROM stg_pan_numbers_dataset
WHERE pan_number IS NULL OR TRIM(pan_number) = '';
```

---

## 3) Find duplicates

```sql
SELECT pan_number, COUNT(*) AS occurrences
FROM stg_pan_numbers_dataset
GROUP BY pan_number
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;
```

**Why:**

* `GROUP BY` collapses identical values.
* `COUNT(*)` tells you how many times each appears.
* `HAVING COUNT(*) > 1` filters to only duplicates.

> Alternative (flags duplicates without collapsing rows):

```sql
SELECT pan_number,
       COUNT(*) OVER (PARTITION BY pan_number) AS occurrences
FROM stg_pan_numbers_dataset;
```

---

## 4) Detect leading/trailing spaces

```sql
SELECT *
FROM stg_pan_numbers_dataset
WHERE pan_number <> TRIM(pan_number);
```

**Why:**
`TRIM` removes spaces at both ends. If trimmed value differs, there were extra spaces.

---

## 5) Detect wrong case (should be uppercase)

```sql
SELECT *
FROM stg_pan_numbers_dataset
WHERE pan_number <> UPPER(pan_number);
```

**Why:**
PANs are uppercase by specification. This finds rows not in uppercase.

---

## 6) Produce a **cleaned** set (normalized values)

```sql
-- This is a SELECT (not a table) that normalizes values:
SELECT DISTINCT UPPER(TRIM(pan_number)) AS pan_number
FROM stg_pan_numbers_dataset
WHERE pan_number IS NOT NULL
  AND TRIM(pan_number) <> '';
```

**Why:**

* `TRIM` removes stray spaces.
* `UPPER` standardizes case.
* `IS NOT NULL` and `<> ''` drop NULLs/blanks.
* `DISTINCT` removes duplicates **after** normalization.

> Note: Using `DISTINCT` means later counts reflect **unique cleaned PANs**, not raw rows. That’s fine—just be explicit in your summary.

---

## 7) Function: adjacent duplicate characters

```sql
CREATE OR REPLACE FUNCTION fn_check_adjacent_characters(p_str TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
  FOR i IN 1 .. (LENGTH(p_str) - 1) LOOP
    IF SUBSTRING(p_str, i, 1) = SUBSTRING(p_str, i + 1, 1) THEN
      RETURN TRUE;  -- Found two identical adjacent characters
    END IF;
  END LOOP;
  RETURN FALSE;     -- No adjacent duplicates found
END;
$$;
```

**What it does:**
Returns **TRUE** if **any** adjacent pair of characters in `p_str` are the same (e.g., `AA`, `11`). Otherwise FALSE.

**Why:**
One project rule is “**no adjacent identical alphabets**” and “**no adjacent identical digits**”. This function enforces both with one pass.

> You later filter with `= FALSE` to **allow only strings without adjacent duplicates**.
> Complexity is O(n); efficient for 10-char PANs.

---

## 8) Function: strictly sequential characters

```sql
CREATE OR REPLACE FUNCTION fn_check_sequential_characters(p_str TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
  FOR i IN 1 .. (LENGTH(p_str) - 1) LOOP
    -- Compare ASCII codes of consecutive characters
    IF ASCII(SUBSTRING(p_str, i + 1, 1)) - ASCII(SUBSTRING(p_str, i, 1)) <> 1 THEN
      RETURN FALSE;  -- As soon as any step isn't +1, it's not a full sequence
    END IF;
  END LOOP;
  RETURN TRUE;       -- Entire string is a strict +1 sequence
END;
$$;
```

**What it does:**
Returns **TRUE** only if the **entire** input is a strict ascending sequence (e.g., `ABCDE`, `2345`). If any step breaks the pattern, returns FALSE.

**Why:**
Your rule says: “All five letters must **not** form a sequence” and “All four digits must **not** form a sequence.” We’ll apply this function to the **first 5** and **next 4** characters separately and require it to be **FALSE**.

> Works for uppercase A–Z and digits 0–9 because their ASCII codes are consecutive in each range.

---

## 9) PAN structure regex

```sql
SELECT *
FROM stg_pan_numbers_dataset
WHERE pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]$';
```

**Why:**
This checks only the **shape**:

* `^` and `$` anchor the start and end (no extra chars).
* `[A-Z]{5}` → first 5 are uppercase letters.
* `[0-9]{4}` → next 4 are digits.
* `[A-Z]`    → last is an uppercase letter.

> This **doesn’t** check adjacency or sequences. That’s why we use the two functions as well.

---

## 10) Build a labeled view (Valid vs Invalid)

```sql
CREATE OR REPLACE VIEW vw_valid_invalid_pans AS
WITH cte_cleaned_pan AS (
  SELECT DISTINCT UPPER(TRIM(pan_number)) AS pan_number
  FROM stg_pan_numbers_dataset
  WHERE pan_number IS NOT NULL
    AND TRIM(pan_number) <> ''
),
cte_valid_pans AS (
  SELECT *
  FROM cte_cleaned_pan
  WHERE fn_check_adjacent_characters(pan_number) = FALSE
    AND fn_check_sequential_characters(SUBSTRING(pan_number, 1, 5)) = FALSE  -- letters not full sequence
    AND fn_check_sequential_characters(SUBSTRING(pan_number, 6, 4)) = FALSE  -- digits not full sequence
    AND pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'                               -- structural regex
)
SELECT cln.pan_number,
       CASE WHEN vld.pan_number IS NOT NULL THEN 'Valid PAN'
            ELSE 'Invalid PAN'
       END AS status
FROM cte_cleaned_pan cln
LEFT JOIN cte_valid_pans vld
  ON vld.pan_number = cln.pan_number;
```

**Why this pattern:**

* **`cte_cleaned_pan`** centralizes normalization (trim + upper + de-dup).
* **`cte_valid_pans`** isolates the **rules** (regex + no adjacency + no sequences).
* Final **LEFT JOIN** keeps **all cleaned PANs**, tagging those that pass the rules as **Valid**, the rest as **Invalid**.

> Why not a single big `CASE`?
> This modular approach is **easier to read, test, and reuse**. You can query `cte_valid_pans` directly to see exactly what passed.

---

## 11) Summary report(s)

### (A) Summary by **unique cleaned PANs** (matches the view)

```sql
WITH summary AS (
  SELECT
    COUNT(*) FILTER (WHERE status = 'Valid PAN')   AS total_valid_pans,
    COUNT(*) FILTER (WHERE status = 'Invalid PAN') AS total_invalid_pans
  FROM vw_valid_invalid_pans
),
totals AS (
  SELECT COUNT(*) AS total_process_records
  FROM stg_pan_numbers_dataset
),
missing AS (
  SELECT COUNT(*) AS total_missing_pans
  FROM stg_pan_numbers_dataset
  WHERE pan_number IS NULL OR TRIM(pan_number) = ''
)
SELECT
  totals.total_process_records,
  summary.total_valid_pans,
  summary.total_invalid_pans,
  missing.total_missing_pans
FROM totals, summary, missing;
```

**What this tells you:**

* `total_process_records` → **raw** rows loaded.
* `total_valid_pans` / `total_invalid_pans` → **unique cleaned** PANs, after normalization and de-dup.
* `total_missing_pans` → raw rows that were NULL/blank.

> Why split like this?
> Avoids the earlier pitfall where `missing` was computed as *raw − (valid + invalid)*, which accidentally treats **duplicates** as “missing”. Here, **missing** is measured **directly**, so it’s accurate.

### (B) Optional: Summary by **raw records** (including duplicates)

If you want to know **how many raw rows** were valid/invalid (i.e., after normalization, does each raw row map to a valid PAN?), you can join raw → view:

```sql
WITH cleaned AS (
  SELECT
    *,
    NULLIF(TRIM(pan_number), '') AS trimmed
  FROM stg_pan_numbers_dataset
),
labeled AS (
  SELECT c.*,
         v.status
  FROM cleaned c
  LEFT JOIN vw_valid_invalid_pans v
    ON UPPER(c.trimmed) = v.pan_number
)
SELECT
  COUNT(*)                                                AS total_process_records,
  COUNT(*) FILTER (WHERE trimmed IS NULL)                 AS total_missing_pans,      -- NULL or blank
  COUNT(*) FILTER (WHERE trimmed IS NOT NULL AND status = 'Valid PAN')   AS total_valid_rows,
  COUNT(*) FILTER (WHERE trimmed IS NOT NULL AND status = 'Invalid PAN') AS total_invalid_rows
FROM labeled;
```

