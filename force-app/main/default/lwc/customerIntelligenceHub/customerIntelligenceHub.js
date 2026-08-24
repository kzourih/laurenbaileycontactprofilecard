import { LightningElement, api, wire } from 'lwc';
import getCustomerIntelligence from '@salesforce/apex/CustomerIntelligenceHubController.getCustomerIntelligence';

export default class CustomerIntelligenceHub extends LightningElement {
    @api recordId;
    @api accentColor = '#3A49DA';
    @api backgroundImage = 'https://images.unsplash.com/photo-1501594907352-04cda38ebc29?w=800&h=300&fit=crop&crop=center';

    // ── Editable demo overrides ──
    @api tierLabel = 'Platinum';
    @api memberSince = '';
    @api overrideOpenCases = '';
    @api overrideHighPriorityCases = '';
    @api overrideCasesJson = '';
    @api overrideLoansJson = '';

    intel;
    error;
    activeSection = 'support';

    @wire(getCustomerIntelligence, { contactId: '$recordId' })
    wiredIntel({ error, data }) {
        if (data) {
            this.intel = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.intel = undefined;
        }
    }

    // ── State ──
    get isLoaded() { return this.intel != null; }
    get hasError() { return this.error != null; }

    // ── Section toggle ──
    get isSupportActive() { return this.activeSection === 'support'; }
    get isFinancialActive() { return this.activeSection === 'financial'; }

    handleSectionClick(event) {
        this.activeSection = event.currentTarget.dataset.section;
    }

    get supportTabClass() { return this.activeSection === 'support' ? 'nav-tab nav-tab-active' : 'nav-tab'; }
    get financialTabClass() { return this.activeSection === 'financial' ? 'nav-tab nav-tab-active' : 'nav-tab'; }

    // ── Banner ──
    get bannerStyle() {
        if (!this.backgroundImage) return '';
        return `background-image: url(${this.backgroundImage})`;
    }

    // ── Identity ──
    get hasPhoto() { return this.intel && this.intel.photoUrl; }
    get initials() {
        if (!this.intel) return '';
        const f = this.intel.firstName ? this.intel.firstName.charAt(0) : '';
        const l = this.intel.name ? this.intel.name.split(' ').pop().charAt(0) : '';
        return (f + l).toUpperCase();
    }

    // ── Badges ──
    get displayTier() { return this.tierLabel || ''; }
    get displayMemberSince() {
        if (this.memberSince) return this.memberSince;
        return this.intel ? this.intel.customerSinceYear : '';
    }
    get showBadges() { return this.displayTier || this.displayMemberSince; }

    // ── Support (with overrides) ──
    get displayOpenCases() {
        if (this.overrideOpenCases !== '' && this.overrideOpenCases != null) return this.overrideOpenCases;
        return this.intel ? this.intel.openCaseCount : 0;
    }
    get displayHighPriorityCases() {
        if (this.overrideHighPriorityCases !== '' && this.overrideHighPriorityCases != null) return this.overrideHighPriorityCases;
        return this.intel ? this.intel.highPriorityCaseCount : 0;
    }
    get hasCases() { return this.intel && this.intel.totalCaseCount > 0; }
    get displayCases() {
        if (this.overrideCasesJson) {
            try {
                const parsed = JSON.parse(this.overrideCasesJson);
                return parsed.map(cs => ({
                    ...cs,
                    priorityClass: (cs.priority === 'High' || cs.priority === 'Critical')
                        ? 'priority-indicator priority-high'
                        : cs.priority === 'Medium' ? 'priority-indicator priority-medium'
                        : 'priority-indicator priority-low',
                    statusClass: cs.isOpen ? 'status-tag status-open' : 'status-tag status-closed'
                }));
            } catch (e) { /* fall through to live data */ }
        }
        return this.casesWithStyle;
    }
    get casesWithStyle() {
        if (!this.intel || !this.intel.recentCases) return [];
        return this.intel.recentCases.map(cs => ({
            ...cs,
            priorityClass: (cs.priority === 'High' || cs.priority === 'Critical')
                ? 'priority-indicator priority-high'
                : cs.priority === 'Medium' ? 'priority-indicator priority-medium'
                : 'priority-indicator priority-low',
            statusClass: cs.isOpen ? 'status-tag status-open' : 'status-tag status-closed'
        }));
    }

    // ── Financial (with overrides) ──
    get hasLoans() { return this.intel && this.intel.loanCount > 0; }
    get displayLoans() {
        if (this.overrideLoansJson) {
            try {
                const parsed = JSON.parse(this.overrideLoansJson);
                return parsed.map(l => ({
                    ...l,
                    formattedBalance: this.formatCurrency(l.currentBalance),
                    formattedOriginal: this.formatCurrency(l.originalAmount),
                    paidPercent: l.originalAmount > 0
                        ? Math.round(((l.originalAmount - l.currentBalance) / l.originalAmount) * 100) : 0,
                    paidBarStyle: l.originalAmount > 0
                        ? `width: ${Math.round(((l.originalAmount - l.currentBalance) / l.originalAmount) * 100)}%` : 'width: 0%'
                }));
            } catch (e) { /* fall through to live data */ }
        }
        return this.loansWithStyle;
    }
    get loansWithStyle() {
        if (!this.intel || !this.intel.loans) return [];
        return this.intel.loans.map(l => ({
            ...l,
            formattedBalance: this.formatCurrency(l.currentBalance),
            formattedOriginal: this.formatCurrency(l.originalAmount),
            paidPercent: l.originalAmount > 0
                ? Math.round(((l.originalAmount - l.currentBalance) / l.originalAmount) * 100) : 0,
            paidBarStyle: l.originalAmount > 0
                ? `width: ${Math.round(((l.originalAmount - l.currentBalance) / l.originalAmount) * 100)}%` : 'width: 0%'
        }));
    }
    get displayTotalBalance() {
        if (this.overrideLoansJson) {
            try {
                const parsed = JSON.parse(this.overrideLoansJson);
                const total = parsed.reduce((sum, l) => sum + (l.currentBalance || 0), 0);
                return this.formatCurrency(total);
            } catch (e) { /* fall through */ }
        }
        return this.formatCurrency(this.intel ? this.intel.totalLoanBalance : 0);
    }

    // ── Utility ──
    formatCurrency(val) {
        if (val == null || val === 0) return '$0';
        if (val >= 1000000) return '$' + (val / 1000000).toFixed(1) + 'M';
        if (val >= 1000) return '$' + (val / 1000).toFixed(1) + 'K';
        return '$' + val.toFixed(0);
    }
}