public with sharing class CustomerIntelligenceHubController {

    @AuraEnabled(cacheable=true)
    public static CustomerIntel getCustomerIntelligence(Id contactId) {
        CustomerIntel intel = new CustomerIntel();

        // ── Contact core ──
        Contact c = [
            SELECT Id, Name, FirstName, LastName, Title, Email, Phone, MobilePhone,
                   Department, MailingCity, MailingState, Birthdate, LeadSource,
                   Account.Name, Account.Industry,
                   SDO_Cust360_Contact_Picture_URL__c,
                   SDO_Cust360_CSAT__c, SDO_Cust360_ChurnRisk__c,
                   SDO_Cust360_Metric1__c, SDO_Cust360_Metric2__c,
                   SDO_Certification_Level_c__c,
                   SDO_PA_Inclusive_Pronouns__c,
                   SDO_PA_Preferred_Contact_Channel__c,
                   CreatedDate
            FROM Contact WHERE Id = :contactId LIMIT 1
        ];

        intel.name = c.Name;
        intel.firstName = c.FirstName;
        intel.title = c.Title;
        intel.email = c.Email;
        intel.phone = c.Phone;
        intel.department = c.Department;
        intel.photoUrl = c.SDO_Cust360_Contact_Picture_URL__c;
        intel.accountName = c.Account != null ? c.Account.Name : '';
        intel.industry = c.Account != null ? c.Account.Industry : '';
        intel.pronouns = c.SDO_PA_Inclusive_Pronouns__c;
        intel.preferredChannel = c.SDO_PA_Preferred_Contact_Channel__c;
        intel.certificationLevel = c.SDO_Certification_Level_c__c;

        // Location
        String city = c.MailingCity != null ? c.MailingCity : '';
        String st = c.MailingState != null ? c.MailingState : '';
        intel.location = String.isNotBlank(city) && String.isNotBlank(st)
            ? city + ', ' + st : city + st;

        // Customer since (year from CreatedDate or birthdate-based tenure)
        if (c.CreatedDate != null) {
            intel.customerSinceYear = String.valueOf(c.CreatedDate.year());
        }

        // Health scores
        intel.csatScore = c.SDO_Cust360_CSAT__c;
        intel.churnRisk = c.SDO_Cust360_ChurnRisk__c;
        intel.loyaltyTier = c.SDO_Cust360_Metric1__c;
        intel.lifetimeValue = c.SDO_Cust360_Metric2__c;

        // ── Health score interpretation ──
        if (intel.csatScore != null) {
            intel.csatTrend = intel.csatScore >= 80 ? 'Excellent' :
                              intel.csatScore >= 60 ? 'Good' :
                              intel.csatScore >= 40 ? 'Fair' : 'Needs Attention';
        }
        if (intel.churnRisk != null) {
            intel.riskLevel = intel.churnRisk <= 25 ? 'Low' :
                              intel.churnRisk <= 50 ? 'Moderate' :
                              intel.churnRisk <= 75 ? 'Elevated' : 'Critical';
        }

        // ── Cases ──
        List<Case> allCases = [
            SELECT Id, CaseNumber, Subject, Status, Priority, CreatedDate, ClosedDate
            FROM Case WHERE ContactId = :contactId
            ORDER BY CreatedDate DESC LIMIT 20
        ];

        Integer openCount = 0;
        Integer closedCount = 0;
        Integer highPriorityOpen = 0;
        intel.recentCases = new List<CaseSummary>();

        for (Case cs : allCases) {
            if (cs.Status == 'Closed') {
                closedCount++;
            } else {
                openCount++;
                if (cs.Priority == 'High' || cs.Priority == 'Critical') {
                    highPriorityOpen++;
                }
            }
            if (intel.recentCases.size() < 3) {
                CaseSummary s = new CaseSummary();
                s.id = cs.Id;
                s.caseNumber = cs.CaseNumber;
                s.subject = cs.Subject;
                s.status = cs.Status;
                s.priority = cs.Priority;
                s.isOpen = cs.Status != 'Closed';
                intel.recentCases.add(s);
            }
        }
        intel.openCaseCount = openCount;
        intel.closedCaseCount = closedCount;
        intel.highPriorityCaseCount = highPriorityOpen;
        intel.totalCaseCount = allCases.size();

        // ── Opportunities ──
        List<OpportunityContactRole> roles = [
            SELECT Opportunity.Id, Opportunity.Name, Opportunity.Amount,
                   Opportunity.StageName, Opportunity.CloseDate, Opportunity.IsClosed, Opportunity.IsWon
            FROM OpportunityContactRole
            WHERE ContactId = :contactId
            ORDER BY Opportunity.CloseDate DESC LIMIT 10
        ];

        Decimal totalPipeline = 0;
        Decimal totalWon = 0;
        Integer wonCount = 0;
        Integer activeDealCount = 0;
        intel.recentDeals = new List<DealSummary>();

        for (OpportunityContactRole r : roles) {
            Opportunity o = r.Opportunity;
            DealSummary d = new DealSummary();
            d.id = o.Id;
            d.name = o.Name;
            d.amount = o.Amount;
            d.stage = o.StageName;
            d.closeDate = o.CloseDate;
            d.isWon = o.IsWon;
            d.isClosed = o.IsClosed;

            if (o.IsWon) {
                totalWon += o.Amount != null ? o.Amount : 0;
                wonCount++;
            } else if (!o.IsClosed) {
                totalPipeline += o.Amount != null ? o.Amount : 0;
                activeDealCount++;
            }

            if (intel.recentDeals.size() < 4) {
                intel.recentDeals.add(d);
            }
        }
        intel.totalPipeline = totalPipeline;
        intel.totalWonRevenue = totalWon;
        intel.wonDealCount = wonCount;
        intel.activeDealCount = activeDealCount;

        // ── Assets ──
        List<Asset> assets = [
            SELECT Id, Name, Status, Product2.Name, PurchaseDate
            FROM Asset WHERE ContactId = :contactId
            ORDER BY PurchaseDate DESC LIMIT 10
        ];
        intel.totalAssetCount = assets.size();
        Integer installedCount = 0;
        intel.recentAssets = new List<AssetSummary>();
        for (Asset a : assets) {
            if (a.Status == 'Installed') installedCount++;
            if (intel.recentAssets.size() < 4) {
                AssetSummary as2 = new AssetSummary();
                as2.id = a.Id;
                as2.name = a.Name;
                as2.status = a.Status;
                as2.productName = a.Product2 != null ? a.Product2.Name : a.Name;
                as2.purchaseDate = a.PurchaseDate;
                intel.recentAssets.add(as2);
            }
        }
        intel.installedAssetCount = installedCount;

        // ── Financial (Loans) ──
        List<Loan__c> loans = [
            SELECT Id, Name, Loan_Type__c, Loan_Status__c,
                   Original_Amount__c, Current_Balance__c, Interest_Rate__c
            FROM Loan__c WHERE Contact__c = :contactId
            ORDER BY Original_Amount__c DESC LIMIT 5
        ];
        Decimal totalBalance = 0;
        Decimal totalOriginal = 0;
        intel.loans = new List<LoanSummary>();
        for (Loan__c l : loans) {
            LoanSummary ls = new LoanSummary();
            ls.id = l.Id;
            ls.name = l.Name;
            ls.loanType = l.Loan_Type__c;
            ls.status = l.Loan_Status__c;
            ls.originalAmount = l.Original_Amount__c;
            ls.currentBalance = l.Current_Balance__c;
            ls.interestRate = l.Interest_Rate__c;
            if (l.Current_Balance__c != null) totalBalance += l.Current_Balance__c;
            if (l.Original_Amount__c != null) totalOriginal += l.Original_Amount__c;
            intel.loans.add(ls);
        }
        intel.totalLoanBalance = totalBalance;
        intel.totalLoanOriginal = totalOriginal;
        intel.loanCount = loans.size();

        // ── Engagement (Campaigns) ──
        List<CampaignMember> members = [
            SELECT Campaign.Name, Campaign.Type, Campaign.Status, Status
            FROM CampaignMember WHERE ContactId = :contactId LIMIT 5
        ];
        intel.campaignCount = members.size();
        intel.campaigns = new List<CampaignSummary>();
        for (CampaignMember cm : members) {
            CampaignSummary cs2 = new CampaignSummary();
            cs2.name = cm.Campaign.Name;
            cs2.campaignType = cm.Campaign.Type;
            cs2.campaignStatus = cm.Campaign.Status;
            cs2.memberStatus = cm.Status;
            intel.campaigns.add(cs2);
        }

        // ── Next Activity ──
        List<Task> upcoming = [
            SELECT Id, Subject, ActivityDate, Status, Type
            FROM Task WHERE WhoId = :contactId
            AND Status != 'Completed'
            ORDER BY ActivityDate ASC LIMIT 1
        ];
        if (!upcoming.isEmpty()) {
            intel.nextActivitySubject = upcoming[0].Subject;
            intel.nextActivityDate = upcoming[0].ActivityDate;
            intel.nextActivityType = upcoming[0].Type;
        }

        // ── Last completed activity ──
        List<Task> completed = [
            SELECT Subject, ActivityDate FROM Task
            WHERE WhoId = :contactId AND Status = 'Completed'
            ORDER BY ActivityDate DESC LIMIT 1
        ];
        if (!completed.isEmpty()) {
            intel.lastActivitySubject = completed[0].Subject;
            intel.lastActivityDate = completed[0].ActivityDate;
        }

        return intel;
    }

    // ── DTOs ──

    public class CustomerIntel {
        // Identity
        @AuraEnabled public String name;
        @AuraEnabled public String firstName;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String department;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String accountName;
        @AuraEnabled public String industry;
        @AuraEnabled public String location;
        @AuraEnabled public String pronouns;
        @AuraEnabled public String preferredChannel;
        @AuraEnabled public String certificationLevel;
        @AuraEnabled public String customerSinceYear;

        // Health
        @AuraEnabled public Decimal csatScore;
        @AuraEnabled public Decimal churnRisk;
        @AuraEnabled public String loyaltyTier;
        @AuraEnabled public String lifetimeValue;
        @AuraEnabled public String csatTrend;
        @AuraEnabled public String riskLevel;

        // Cases
        @AuraEnabled public Integer openCaseCount = 0;
        @AuraEnabled public Integer closedCaseCount = 0;
        @AuraEnabled public Integer highPriorityCaseCount = 0;
        @AuraEnabled public Integer totalCaseCount = 0;
        @AuraEnabled public List<CaseSummary> recentCases;

        // Revenue
        @AuraEnabled public Decimal totalPipeline = 0;
        @AuraEnabled public Decimal totalWonRevenue = 0;
        @AuraEnabled public Integer wonDealCount = 0;
        @AuraEnabled public Integer activeDealCount = 0;
        @AuraEnabled public List<DealSummary> recentDeals;

        // Assets
        @AuraEnabled public Integer totalAssetCount = 0;
        @AuraEnabled public Integer installedAssetCount = 0;
        @AuraEnabled public List<AssetSummary> recentAssets;

        // Financial
        @AuraEnabled public Decimal totalLoanBalance = 0;
        @AuraEnabled public Decimal totalLoanOriginal = 0;
        @AuraEnabled public Integer loanCount = 0;
        @AuraEnabled public List<LoanSummary> loans;

        // Engagement
        @AuraEnabled public Integer campaignCount = 0;
        @AuraEnabled public List<CampaignSummary> campaigns;

        // Activity
        @AuraEnabled public String nextActivitySubject;
        @AuraEnabled public Date nextActivityDate;
        @AuraEnabled public String nextActivityType;
        @AuraEnabled public String lastActivitySubject;
        @AuraEnabled public Date lastActivityDate;
    }

    public class CaseSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Boolean isOpen;
    }

    public class DealSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String stage;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Boolean isWon;
        @AuraEnabled public Boolean isClosed;
    }

    public class AssetSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String productName;
        @AuraEnabled public Date purchaseDate;
    }

    public class LoanSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String loanType;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal originalAmount;
        @AuraEnabled public Decimal currentBalance;
        @AuraEnabled public Decimal interestRate;
    }

    public class CampaignSummary {
        @AuraEnabled public String name;
        @AuraEnabled public String campaignType;
        @AuraEnabled public String campaignStatus;
        @AuraEnabled public String memberStatus;
    }
}