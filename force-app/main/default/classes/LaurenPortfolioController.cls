public with sharing class LaurenPortfolioController {
    public class PortfolioSummary {
        @AuraEnabled public String customerName { get; set; }
        @AuraEnabled public String customerTier { get; set; }
        @AuraEnabled public String relationshipManager { get; set; }
        @AuraEnabled public Decimal totalRelationshipValue { get; set; }
        @AuraEnabled public Decimal investmentsValue { get; set; }
        @AuraEnabled public Decimal depositsValue { get; set; }
        @AuraEnabled public Decimal loansOutstanding { get; set; }
        @AuraEnabled public Decimal monthlyChange { get; set; }
        @AuraEnabled public Decimal ytdReturnPercent { get; set; }
        @AuraEnabled public Boolean complianceCleared { get; set; }
        @AuraEnabled public Decimal averageRating { get; set; }
        @AuraEnabled public List<HoldingInfo> holdings { get; set; }
        @AuraEnabled public HelocInfo heloc { get; set; }
        @AuraEnabled public List<SatisfactionInfo> satisfactionSurveys { get; set; }
    }

    public class HoldingInfo {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String assetClass { get; set; }
        @AuraEnabled public Decimal marketValue { get; set; }
        @AuraEnabled public Decimal returnPercent { get; set; }
    }

    public class HelocInfo {
        @AuraEnabled public Decimal approvedLimit { get; set; }
        @AuraEnabled public Decimal amountDrawn { get; set; }
        @AuraEnabled public Decimal availableCredit { get; set; }
        @AuraEnabled public Decimal interestRate { get; set; }
        @AuraEnabled public Decimal nextPaymentAmount { get; set; }
        @AuraEnabled public Date nextPaymentDate { get; set; }
        @AuraEnabled public String complianceStatus { get; set; }
    }

    public class SatisfactionInfo {
        @AuraEnabled public Integer rating { get; set; }
        @AuraEnabled public String surveyType { get; set; }
        @AuraEnabled public String sentiment { get; set; }
        @AuraEnabled public String comments { get; set; }
        @AuraEnabled public Date surveyDate { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static PortfolioSummary getPortfolioSummary(Id customerId) {
        if (customerId == null) {
            return null;
        }

        List<Bank_Customer__c> customers = [
            SELECT Id, Full_Name__c, Customer_Tier__c, Relationship_Manager__c, KYC_Verified_Date__c
            FROM Bank_Customer__c
            WHERE Id = :customerId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (customers.isEmpty()) {
            return null;
        }
        Bank_Customer__c customer = customers[0];

        List<Investment_Portfolio__c> portfolios = [
            SELECT Id, Portfolio_Name__c, Total_Value__c, Cash_Balance__c, YTD_Return_Percent__c, Monthly_Change__c,
                (SELECT Id, Holding_Name__c, Asset_Class__c, Market_Value__c, Unrealized_Return_Percent__c
                 FROM Investment_Holdings__r
                 ORDER BY Market_Value__c DESC)
            FROM Investment_Portfolio__c
            WHERE Customer__c = :customer.Id
            WITH SECURITY_ENFORCED
            ORDER BY As_Of_Date__c DESC, CreatedDate DESC
            LIMIT 1
        ];

        List<Loan_Application__c> loans = [
            SELECT Id, Approved_Limit__c, Amount_Drawn__c, Interest_Rate__c, Next_Payment_Amount__c,
                Next_Payment_Date__c, Compliance_Status__c
            FROM Loan_Application__c
            WHERE Customer__c = :customer.Id
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        List<Compliance_Check__c> complianceChecks = [
            SELECT Id, Check_Type__c, Pass_Status__c, Expiry_Date__c
            FROM Compliance_Check__c
            WHERE Customer__c = :customer.Id
              AND Pass_Status__c = true
              AND Expiry_Date__c >= :Date.today()
              AND Check_Type__c IN ('KYC Verification', 'AML Screening', 'OFAC Sanctions Check')
            WITH SECURITY_ENFORCED
        ];

        List<Customer_Satisfaction__c> surveys = [
            SELECT Id, Rating__c, Survey_Type__c, Sentiment__c, Feedback_Comments__c, Survey_Date__c
            FROM Customer_Satisfaction__c
            WHERE Customer__c = :customer.Id
            WITH SECURITY_ENFORCED
            ORDER BY Survey_Date__c DESC, CreatedDate DESC
        ];

        PortfolioSummary summary = new PortfolioSummary();
        summary.customerName = customer.Full_Name__c;
        summary.customerTier = customer.Customer_Tier__c;
        summary.relationshipManager = customer.Relationship_Manager__c;
        summary.holdings = new List<HoldingInfo>();
        summary.satisfactionSurveys = new List<SatisfactionInfo>();

        Investment_Portfolio__c portfolio = portfolios.isEmpty() ? null : portfolios[0];
        Loan_Application__c helocLoan = loans.isEmpty() ? null : loans[0];

        Decimal investmentsValue = portfolio?.Total_Value__c ?? 0;
        Decimal cashBalance = portfolio?.Cash_Balance__c ?? 0;
        Decimal loansOutstanding = helocLoan?.Amount_Drawn__c ?? 0;
        Decimal depositsValue = 0;

        if (portfolio != null && portfolio.Investment_Holdings__r != null) {
            for (Investment_Holding__c holding : portfolio.Investment_Holdings__r) {
                HoldingInfo holdingInfo = new HoldingInfo();
                holdingInfo.name = holding.Holding_Name__c;
                holdingInfo.assetClass = holding.Asset_Class__c;
                holdingInfo.marketValue = holding.Market_Value__c ?? 0;
                holdingInfo.returnPercent = holding.Unrealized_Return_Percent__c ?? 0;
                summary.holdings.add(holdingInfo);

                if (holding.Asset_Class__c == 'Deposits') {
                    depositsValue += (holding.Market_Value__c ?? 0);
                }
            }
        }

        Set<String> validCheckTypes = new Set<String>();
        for (Compliance_Check__c checkRecord : complianceChecks) {
            if (checkRecord.Pass_Status__c == true && checkRecord.Expiry_Date__c != null && checkRecord.Expiry_Date__c >= Date.today()) {
                validCheckTypes.add(checkRecord.Check_Type__c);
            }
        }

        Boolean kycDateCurrent = customer.KYC_Verified_Date__c != null &&
            customer.KYC_Verified_Date__c >= Date.today().addDays(-90);
        summary.complianceCleared = validCheckTypes.contains('KYC Verification')
            && validCheckTypes.contains('AML Screening')
            && validCheckTypes.contains('OFAC Sanctions Check')
            && kycDateCurrent;

        summary.investmentsValue = investmentsValue;
        summary.depositsValue = depositsValue;
        summary.loansOutstanding = loansOutstanding;
        summary.monthlyChange = portfolio?.Monthly_Change__c ?? 0;
        summary.ytdReturnPercent = portfolio?.YTD_Return_Percent__c ?? 0;
        summary.totalRelationshipValue = investmentsValue + cashBalance + depositsValue - loansOutstanding;

        HelocInfo heloc = new HelocInfo();
        heloc.approvedLimit = helocLoan?.Approved_Limit__c ?? 0;
        heloc.amountDrawn = helocLoan?.Amount_Drawn__c ?? 0;
        heloc.availableCredit = heloc.approvedLimit - heloc.amountDrawn;
        heloc.interestRate = helocLoan?.Interest_Rate__c ?? 0;
        heloc.nextPaymentAmount = helocLoan?.Next_Payment_Amount__c ?? 0;
        heloc.nextPaymentDate = helocLoan?.Next_Payment_Date__c;
        heloc.complianceStatus = helocLoan?.Compliance_Status__c;
        summary.heloc = heloc;

        Decimal ratingTotal = 0;
        Integer ratedCount = 0;
        for (Customer_Satisfaction__c survey : surveys) {
            SatisfactionInfo item = new SatisfactionInfo();
            item.rating = survey.Rating__c == null ? null : Integer.valueOf(survey.Rating__c);
            item.surveyType = survey.Survey_Type__c;
            item.sentiment = survey.Sentiment__c;
            item.comments = survey.Feedback_Comments__c;
            item.surveyDate = survey.Survey_Date__c;
            summary.satisfactionSurveys.add(item);

            if (survey.Rating__c != null) {
                ratingTotal += survey.Rating__c;
                ratedCount++;
            }
        }
        summary.averageRating = ratedCount > 0 ? (ratingTotal / ratedCount).setScale(2) : null;

        return summary;
    }

    @AuraEnabled
    public static void submitFeedback(Id customerId, Integer rating, String comments) {
        if (customerId == null || rating == null) {
            throw new AuraHandledException('Customer and rating are required.');
        }
        if (rating < 1 || rating > 5) {
            throw new AuraHandledException('Rating must be between 1 and 5.');
        }
        if (!Schema.sObjectType.Customer_Satisfaction__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to submit feedback.');
        }

        Customer_Satisfaction__c feedback = new Customer_Satisfaction__c(
            Customer__c = customerId,
            Rating__c = rating,
            Survey_Type__c = 'Digital Experience',
            Feedback_Comments__c = comments,
            Survey_Date__c = Date.today(),
            Sentiment__c = rating >= 4 ? 'Positive' : (rating == 3 ? 'Neutral' : 'Detractor')
        );

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<Customer_Satisfaction__c>{ feedback }
        );
        List<SObject> sanitized = decision.getRecords();
        if (sanitized.isEmpty()) {
            throw new AuraHandledException('Feedback could not be submitted.');
        }
        insert sanitized[0];
    }
}