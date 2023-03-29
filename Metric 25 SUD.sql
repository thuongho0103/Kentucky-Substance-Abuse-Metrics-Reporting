CREATE NONCLUSTERED INDEX TestM25
on Metric25_SUD_Non_Transfer_20172022 (DTE_DISCHARGE)

CREATE NONCLUSTERED INDEX TestM25
on Metric25_SUD_TotalMultipleStays_20172022 (DTE_DISCHARGE)

-- ONLY need to run this 1 
drop table if exists #BEN_IDFemale
select distinct BEN_ID INTO #BEN_IDFemale
from dbo.LDS_OUD where GENDER = 'F' 

DRop TABLE IF ExISTS #Debug
DROP TABLE IF EXISTS #M25Results
CREATE TABLE #M25Results (
	ReportingYear int,
	Denominator int,
	Nominator int	) 

DECLARE @measurementyear int = 2017
WHILE @measurementyear < 2022  
BEGIN 

-- B. Non-Transfer Stays with Discharge date in the period
DROP TABLE IF EXISTS #T2a_acuteYear
DECLARE @measurementbegin datetime2 = datefromparts(@measurementyear,07,01)
DECLARE @measurementend datetime2 = datefromparts(@measurementyear+1,06,30)
SELECT * 
INTO #T2a_acuteYear
	from Metric25_SUD_Non_Transfer_20172022
	where [DTE_DISCHARGE]  between  @measurementbegin  and @measurementend

-- Multiple Transfer Stays with Discharge Date in the Period
DROP TABLE IF EXISTS #T2a_acuteTotalMultipleStays
SELECT * 
INTO #T2a_acuteTotalMultipleStays
FROM Metric25_SUD_TotalMultipleStays_20172022
where cast( [DTE_DISCHARGE] as date)  between   @measurementbegin  and @measurementend

-- Address Admission Date with less than 2 dates
-- Look for the next admission date and last discharge date based on each BEN_ID
-- Find the next admission and last discharge to determine the date difference
DROP TABLE IF EXISTS #GET_NEXT_SPAN 
select span.*
	, LEAD(SPAN.DTE_ADMISSION) OVER (PARTITION BY SPAN.BEN_ID ORDER BY SPAN.DTE_ADMISSION,DTE_DISCHARGE) AS nextAdmitDate
	, LAG(SPAN.DTE_DISCHARGE) OVER (PARTITION BY SPAN.BEN_ID ORDER BY SPAN.DTE_ADMISSION,SPAN.DTE_DISCHARGE) AS lastDischargeDate
	INTO #GET_NEXT_SPAN
	from #T2a_acuteTotalMultipleStays AS SPAN
ORDER BY BEN_ID, DTE_ADMISSION, DTE_DISCHARGE

-- Count the date difference to next Admission Date and last Discharge Date 
DROP TABLE IF EXISTS #DAYS_TO_NEXT_STAY
SELECT
	GNS.*
	, DATEDIFF(DAY, CAST(GNS.DTE_DISCHARGE AS DATE), CAST(GNS.nextAdmitDate AS DATE)) AS daysToNextStay
	-- find the difference between current discharge date and next admit date
	, ABS(DATEDIFF(DAY,CAST(GNS.lastDischargeDate AS DATE) , CAST(GNS.DTE_ADMISSION AS DATE))) AS daysToLastStay
	-- find the difference between current admission date and last discharge date
INTO #DAYS_TO_NEXT_STAY
FROM #GET_NEXT_SPAN AS GNS

drop table if exists #T2a_acuteTotalMultipleStays_YandN
SELECT
	*,
	IIF ( 
	IIF(daysToNextStay < 2, 'Y', 'N') = 'N',
	IIF(daysToLastStay < 2, 'Y', 'N')
	, 'Y'
	)
	AS isDirectTransfer
INTO #T2a_acuteTotalMultipleStays_YandN
FROM #DAYS_TO_NEXT_STAY

drop table if exists #T2a_acuteTotalMultipleStays_Nonly
select BEN_ID, DTE_ADMISSION, DTE_DISCHARGE,DTE_DEATH,CDE_PROC_PRIM, CDE_DIAG_01
into #T2a_acuteTotalMultipleStays_Nonly
from #T2a_acuteTotalMultipleStays_YandN
where isDirectTransfer = 'N'
order by BEN_ID, DTE_ADMISSION,DTE_DISCHARGE

-- this table will be used for assessing multiple transfer with one index hospital stay
drop table if exists #T2a_acuteTotalMultipleStays_Yonly
select [CLAIM_GUID], [NUM_DTL],[BEN_ID], [DTE_FIRST_SVC],[DTE_LAST_SVC],[DTE_ADMISSION], [DTE_DISCHARGE],[CE30D],[CDE_COUNTY],[DTE_BIRTH],[DTE_DEATH],[AGE_DFS],[PERF_PROV_KEY],[BILL_PROV_KEY],[ID_PRESCRIBER],[CDE_PROC_PRIM],[CDE_REVENUE],[CDE_CLM_TYPE],[CDE_ENC_TYPE],[CDE_NDC],[DSC_NDC],[CDE_POS], [DAYS_SUPPL],[QTY],[AMT_PAID],[AMT_ENCOUNTER],[CDE_DIAG_01],[CDE_DIAG_02],[CDE_DIAG_03],[CDE_DIAG_04],[CDE_DIAG_05],[CDE_DIAG_06],[CDE_DIAG_07],[CDE_DIAG_08],[CDE_DIAG_09],[CDE_DIAG_10],[CDE_DIAG_11],[CDE_DIAG_12],[CDE_DIAG_13],[CDE_DIAG_14],[CDE_DIAG_15],[CDE_DIAG_16],[CDE_DIAG_17],[CDE_DIAG_18],[CDE_DIAG_19],[CDE_DIAG_20],[CDE_DIAG_21],[CDE_DIAG_22],[CDE_DIAG_23],[CDE_DIAG_24],[CDE_DIAG_25] 
into #T2a_acuteTotalMultipleStays_Yonly
from #T2a_acuteTotalMultipleStays_YandN
where isDirectTransfer = 'Y'
order by BEN_ID, DTE_ADMISSION,DTE_DISCHARGE

drop table if exists #Temp
select BEN_ID, DTE_ADMISSION, DTE_DISCHARGE,DTE_DEATH,CDE_PROC_PRIM, CDE_DIAG_01, 
row_number() over (partition by BEN_ID order by BEN_ID,DTE_ADMISSION,DTE_DISCHARGE) as RowNo_BEN
	into #Temp
	from #T2a_acuteTotalMultipleStays_Yonly
order by BEN_ID

delete from #Temp
where BEN_ID not in (select distinct BEN_ID from #Temp where RowNo_BEN > 1)

drop table if exists #T1
select BEN_ID, DTE_ADMISSION, DTE_DISCHARGE,DTE_DEATH,CDE_PROC_PRIM, CDE_DIAG_01, 
row_number() over (partition by BEN_ID order by BEN_ID,DTE_ADMISSION,DTE_DISCHARGE) as RowNo_BEN,
row_number() over (order by BEN_ID,DTE_ADMISSION,DTE_DISCHARGE) as RowNo
	into #T1
	from #Temp
order by BEN_ID

DROP TABLE IF EXISTS #GET_NEXT_SPAN1
select span.*
	, LEAD(SPAN.DTE_ADMISSION) OVER (PARTITION BY SPAN.BEN_ID ORDER BY SPAN.DTE_ADMISSION,DTE_DISCHARGE) AS nextAdmitDate
	, LAG(SPAN.DTE_DISCHARGE) OVER (PARTITION BY SPAN.BEN_ID ORDER BY SPAN.DTE_ADMISSION,SPAN.DTE_DISCHARGE) AS lastDischargeDate
	INTO #GET_NEXT_SPAN1
	from #T1 AS SPAN
ORDER BY BEN_ID, DTE_ADMISSION, DTE_DISCHARGE

-- Count the date difference to next Admission Date and last Discharge Date 
DROP TABLE IF EXISTS #DAYS_TO_NEXT_STAY1
SELECT
	GNS.*
	, DATEDIFF(DAY, CAST(GNS.DTE_DISCHARGE AS DATE), CAST(GNS.nextAdmitDate AS DATE)) AS daysToNextStay
	-- find the difference between current discharge date and next admit date
	, ABS(DATEDIFF(DAY,CAST(GNS.lastDischargeDate AS DATE) , CAST(GNS.DTE_ADMISSION AS DATE))) AS daysToLastStay
	-- find the difference between current admission date and last discharge date
INTO #DAYS_TO_NEXT_STAY1
FROM #GET_NEXT_SPAN1 AS GNS

drop table if exists #T2
select * 
into #T2
from #DAYS_TO_NEXT_STAY1

CREATE NONCLUSTERED INDEX NCI_RowNo
ON #T2 (RowNo, RowNo_BEN)

--EXEC tempdb.dbo.sp_help @objname = #T2;


drop table if exists #Debug
CREATE TABLE #Debug (
    BEN_ID uniqueidentifier,
    DTE_ADMISSION datetime2,
	DTE_DISCHARGE datetime2,
	DTE_DEATH datetime2,
	CDE_PROC_PRIM nvarchar(14),
	CDE_DIAG_01 nvarchar(136),
    RowNo_BEN bigint,
	RowNo bigint ,
	nextAdmitDate datetime2,
	lastDischargeDate datetime2,
	daysToNextStay int,
	daysToLastStay int,
	transferno int
);

DECLARE @RowNumberBEN int 
set @RowNumberBEN = (select max(RowNo) from  #T2)

Declare @CountTotalOccurence int 
set @CountTotalOccurence = 1

Declare @transferno int

Declare @n int 

WHILE @CountTotalOccurence <= @RowNumberBEN

	BEGIN
		IF (
			select RowNo_BEN from #T2
			 where  RowNo = @CountTotalOccurence)= 1
			BEGIN 
				Set @transferno = 1
				Set	@n = 0
			END;
		ELSE
			BEGIN
				IF (
					select  daysToLastStay
					from #T2
					where RowNo = @CountTotalOccurence) < 2
					BEGIN 
						set @transferno = @transferno + @n 
					END;
				ELSE IF 
					 (
					select  daysToLastStay 
					from #T2
					where RowNo = @CountTotalOccurence) >= 2
					BEGIN 
						set @n = @n + 1 
						set @transferno = @transferno +@n
						set @n = @n - 1
					END;
			END;
	print @CountTotalOccurence
	print @transferno
	print @n
	INSERT INTO #Debug
	select BEN_ID,DTE_ADMISSION, DTE_DISCHARGE, DTE_DEATH, CDE_PROC_PRIM, CDE_DIAG_01, 
	RowNo_BEN, RowNo, nextAdmitDate, lastDischargeDate,daysToNextStay, daysToLastStay, @transferno
	from #T2
	where  RowNo = @CountTotalOccurence
	Set @CountTotalOccurence = @CountTotalOccurence + 1
	END;

-- test case
--select * from #Debug 
--order by BEN_ID,DTE_ADMISSION, DTE_DISCHARGE

WITH MinMax AS (
	SELECT  BEN_ID,DTE_ADMISSION,DTE_DISCHARGE, transferno,
	    Min_ADMISSION = MIN(DTE_ADMISSION) OVER (PARTITION BY BEN_ID,transferno  ORDER BY BEN_ID, DTE_ADMISSION, DTE_DISCHARGE),
      Max_DISCHARGE = MAX(DTE_DISCHARGE) OVER (PARTITION BY BEN_ID,transferno ORDER BY BEN_ID)
    FROM #Debug
)
 
UPDATE MinMax
SET DTE_ADMISSION = Min_ADMISSION,
    DTE_DISCHARGE = Max_DISCHARGE

--select * from #Debug
-- DROP COLUMN before union tables
ALTER TABLE #Debug
DROP COLUMN RowNo_BEN, RowNo, nextAdmitDate, lastDischargeDate, daysToNextStay, daysToLastStay, transferno

-- UNION all records after updating admission and discharge additional guidance
DROP TABLE IF EXISTS #T2_acuteFinal
Select a.*
INTO #T2_acuteFinal 
FROM (
Select BEN_ID,DTE_ADMISSION, DTE_DISCHARGE, DTE_DEATH, CDE_PROC_PRIM, CDE_DIAG_01 
FROM #T2a_acuteYear
UNION
select * 
from #T2a_acuteTotalMultipleStays_Nonly
UNION
select * 
from #Debug
) a

-- -- Exclude hospital stays where the Index Admission Date is the same as the Index Discharge Date.
-- delete from #T2_acuteFinal
-- where [DTE_ADMISSION] = [DTE_DISCHARGE]
-- 	--ORDER BY BEN_ID, DTE_ADMISSION, DTE_DISCHARGE

-- Step 2d Exclude ben died during the stay
delete from 
#T2_acuteFinal
where DTE_DEATH between DTE_ADMISSION and DTE_DISCHARGE

-- Step 2d Exclude female with pregnancy or perinatal conditions value set.
delete from #T2_acuteFinal --female with pregnancy or perinatal conditions:
where BEN_ID IN (Select distinct BEN_ID FROM #BEN_IDFemale)
AND [CDE_DIAG_01] IN
(select CodeR from [LDS_External].[dbo].[HEDISV5] where Value_Set_Name = 'Pregnancy'
UNION 
select CodeR from [LDS_External].[dbo].[HEDISV5] where Value_Set_Name = 'Perinatal Conditions')


-- Step 3: Count 30 days Readmission
DROP TABLE IF EXISTS #T3_acuteFinal
Select a.*
INTO #T3_acuteFinal 
FROM (
select * 
from #T2a_acuteTotalMultipleStays_Nonly
UNION
select * 
from #Debug) a

-- Remove duplicate of same BEN_ID, DTE_ADMISSION,DTE_DISCHARGE for additional guidance
DELETE FROM #T3_acuteFinal
where BEN_ID in 
(select distinct BEN_ID from 
		(select *, ROW_NUMBER () OVER (PARTITION BY BEN_ID,DTE_ADMISSION,DTE_DISCHARGE ORDER BY BEN_ID, DTE_ADMISSION) as DUP_COUNT 
		from #T3_acuteFinal) a
	WHERE DUP_COUNT >2)

-- Step 3C, Exclue female with Pregnancy or Perinatal Conditions
delete from #T3_acuteFinal 
where BEN_ID IN (Select distinct BEN_ID FROM #BEN_IDFemale)
AND [CDE_DIAG_01] IN
(select CodeR from [LDS_External].[dbo].[HEDISV5] where Value_Set_Name = 'Pregnancy'
UNION 
select CodeR from [LDS_External].[dbo].[HEDISV5] where Value_Set_Name = 'Perinatal Conditions')

-- Exclude planned admission of following:
DELETE FROM #T3_acuteFinal
where
([CDE_DIAG_01] in (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Chemotherapy Encounter')
	   AND [CDE_PROC_PRIM] in (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Chemotherapy Procedure'))
	   or [CDE_DIAG_01] in (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Rehabilitation')
       or [CDE_PROC_PRIM] in (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Kidney Transplant')
	   or [CDE_PROC_PRIM] in (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Bone Marrow Transplant')
	   or [CDE_PROC_PRIM] in (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Kidney Transplant')
	   or [CDE_PROC_PRIM] in (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Organ Transplant Other Than Kidney')
	   or [CDE_PROC_PRIM] in (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Introduction of Autologous Pancreatic Cells')
	   or ([CDE_PROC_PRIM] in (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Potentially Planned Procedures')
		AND [CDE_DIAG_01] NOT IN (select [CodeR] from [dbo].[HEDISV5] where value_set_name ='Acute Condition'))

-- Run lead partition determine an admission date within 30 days after the Index Discharge Date.
DROP TABLE IF EXISTS #GET_NEXT_SPAN2 
select span.*
	, LEAD(SPAN.DTE_ADMISSION) OVER (PARTITION BY SPAN.BEN_ID ORDER BY SPAN.DTE_ADMISSION,DTE_DISCHARGE) AS nextAdmitDate
	INTO #GET_NEXT_SPAN2
	from #T3_acuteFinal AS SPAN
ORDER BY BEN_ID, DTE_ADMISSION, DTE_DISCHARGE

DROP TABLE IF EXISTS #DAYS_TO_NEXT_STAY2
SELECT
	GNS.*
	, DATEDIFF(DAY, CAST(GNS.DTE_DISCHARGE AS DATE), CAST(GNS.nextAdmitDate AS DATE)) AS daysToNextStay
	-- find the difference between current discharge date and next admit date
INTO #DAYS_TO_NEXT_STAY2
FROM #GET_NEXT_SPAN2 AS GNS

INSERT INTO #M25Results (ReportingYear, Denominator, Nominator)
VALUES( @measurementyear, 
(
-- Count number of index hospital stays based on number of BEN_ID, DTE_ADMISSION, DTE_DISCHARGE
SELECT count(*) as Denominator
FROM ( select *, ROW_NUMBER() OVER (PARTITION BY BEN_ID, DTE_ADMISSION, DTE_DISCHARGE ORDER BY BEN_ID, DTE_ADMISSION) 
AS DUP_COUNT from #T2_acuteFinal) x 
WHERE DUP_COUNT = 1
and DTE_DISCHARGE between @measurementbegin and @measurementend 
), 
(
-- Count the number of stays that have admission date within 30 days after the Index Discharge Date
select count(*) as Nominator
from #DAYS_TO_NEXT_STAY2
where daysToNextStay <= 30
and DTE_DISCHARGE between datefromparts(@measurementyear,07,03) and @measurementend
))

SET @measurementyear = @measurementyear +1 
END;

select * from #M25Results