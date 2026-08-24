import { LightningElement, api, wire, track } from 'lwc';
import getPortfolioSummary from '@salesforce/apex/LaurenPortfolioController.getPortfolioSummary';
import submitFeedback from '@salesforce/apex/LaurenPortfolioController.submitFeedback';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class MyPortfolioHome extends LightningElement {
    HARDCODED_LAUREN_CUSTOMER_ID = 'a4sfj00000047VxAAI';
    @api recordId;
    @api customerId;

    @track summary;
    @track selectedRating = 0;
    @track feedbackText = '';
    @track isSubmitting = false;
    @track loadError;

    wiredSummaryResult;

    emojiChoices = [
        { rating: 1, icon: '😕' },
        { rating: 2, icon: '🙂' },
        { rating: 3, icon: '😊' },
        { rating: 4, icon: '😃' },
        { rating: 5, icon: '🤩' }
    ];

    get resolvedCustomerId() {
        const configuredId = this.customerId?.trim();
        if (configuredId) {
            if (configuredId.startsWith('003')) {
                return this.HARDCODED_LAUREN_CUSTOMER_ID;
            }
            return configuredId;
        }

        if (this.recordId?.startsWith('003')) {
            return this.HARDCODED_LAUREN_CUSTOMER_ID;
        }

        return this.recordId || this.HARDCODED_LAUREN_CUSTOMER_ID;
    }

    @wire(getPortfolioSummary, { customerId: '$resolvedCustomerId' })
    wiredSummary(value) {
        this.wiredSummaryResult = value;
        const { data, error } = value;
        if (data) {
            this.summary = data;
            this.loadError = null;
        } else if (error) {
            this.summary = null;
            this.loadError = error;
        }
    }

    get firstName() {
        if (!this.summary?.customerName) {
            return 'Client';
        }
        return this.summary.customerName.split(' ')[0];
    }

    get monthlyDirectionClass() {
        return (this.summary?.monthlyChange || 0) >= 0 ? 'positive' : 'negative';
    }

    get hasSummary() {
        return !!this.summary;
    }

    get holdings() {
        return (this.summary?.holdings || []).map((holding) => ({
            ...holding,
            returnClass: (holding.returnPercent || 0) >= 0 ? 'positive' : 'negative'
        }));
    }

    get hasHoldings() {
        return this.holdings.length > 0;
    }

    get latestSurvey() {
        return this.summary?.satisfactionSurveys?.[0];
    }

    get surveyCount() {
        return this.summary?.satisfactionSurveys?.length || 0;
    }

    get hasSurveys() {
        return this.surveyCount > 0;
    }

    get recentSurveys() {
        return (this.summary?.satisfactionSurveys || []).slice(0, 3);
    }

    get advisorInsights() {
        const insights = [];
        const avg = Number(this.summary?.averageRating || 0);
        const complianceText = this.summary?.complianceCleared ? 'Compliance is currently cleared for HELOC servicing.' : 'Compliance review requires follow-up before product action.';
        const topHolding = this.holdings.length ? this.holdings[0].name : 'No holdings loaded';

        insights.push({ key: 'one', text: `Customer sentiment average is ${avg.toFixed(1)}/5 across ${this.surveyCount} survey(s).` });
        insights.push({ key: 'two', text: `Largest position is ${topHolding}.` });
        insights.push({ key: 'three', text: complianceText });
        insights.push({ key: 'four', text: `HELOC available credit is $${Number(this.summary?.heloc?.availableCredit || 0).toLocaleString()}.` });
        return insights;
    }

    get interactionChannels() {
        const avg = Number(this.summary?.averageRating || 4.5);
        const positiveBias = Math.max(0, Math.min(8, avg - 3));
        const channels = [
            { key: 'voice', name: 'Voice', count: 24, positive: 84 + positiveBias * 2, trend: '+11%' },
            { key: 'chat', name: 'Chat', count: 17, positive: 80 + positiveBias * 2, trend: '+18%' },
            { key: 'email', name: 'Email', count: 12, positive: 87 + positiveBias, trend: '+9%' }
        ];
        return channels.map((channel) => ({
            ...channel,
            positiveRounded: Math.round(channel.positive),
            barStyle: `width: ${Math.round(channel.positive)}%;`
        }));
    }

    get qualityMomentumPath() {
        const surveys = [...(this.summary?.satisfactionSurveys || [])]
            .filter((item) => item?.rating)
            .sort((a, b) => new Date(a.surveyDate) - new Date(b.surveyDate));
        const source = surveys.length >= 2 ? surveys.map((item) => Number(item.rating)) : [3.8, 4.1, 4.0, 4.4, 4.7];
        const widthStep = 75;
        return `M ${source.map((score, index) => `${index * widthStep} ${80 - ((score - 1) / 4) * 60}`).join(' L ')}`;
    }

    get qualityMomentumDelta() {
        const surveys = [...(this.summary?.satisfactionSurveys || [])]
            .filter((item) => item?.rating)
            .sort((a, b) => new Date(a.surveyDate) - new Date(b.surveyDate));
        if (surveys.length >= 2) {
            const first = Number(surveys[0].rating);
            const last = Number(surveys[surveys.length - 1].rating);
            const delta = (last - first).toFixed(1);
            return `${delta > 0 ? '+' : ''}${delta}`;
        }
        return '+0.9';
    }

    get keywordTrends() {
        const comments = (this.summary?.satisfactionSurveys || [])
            .map((item) => item.comments || '')
            .join(' ')
            .toLowerCase();
        const candidates = [
            { key: 'advisor', label: 'Advisor guidance', terms: ['advisor', 'explained', 'guidance'] },
            { key: 'speed', label: 'Decision speed', terms: ['fast', 'quick', 'decision'] },
            { key: 'digital', label: 'Digital workflow', terms: ['upload', 'portal', 'digital', 'clunky'] },
            { key: 'rate', label: 'Rate review', terms: ['rate', 'review'] }
        ];

        return candidates.map((item) => {
            let count = 0;
            item.terms.forEach((term) => {
                if (comments.includes(term)) {
                    count += 1;
                }
            });
            return {
                key: item.key,
                label: item.label,
                mentions: count,
                trend: item.key === 'digital' ? 'Watchlist' : 'Positive Momentum',
                trendClass: item.key === 'digital' ? 'keyword-trend watch' : 'keyword-trend up'
            };
        });
    }

    get customerHealthScore() {
        const avgRating = Number(this.summary?.averageRating || 4.2); // out of 5
        const sentimentScore = Math.min(100, Math.max(0, (avgRating / 5) * 100));
        const complianceScore = this.summary?.complianceCleared ? 100 : 45;
        const engagementBase = Math.min(100, ((this.surveyCount * 12) + (this.holdings.length * 8) + 40));

        const weighted = (sentimentScore * 0.45) + (complianceScore * 0.35) + (engagementBase * 0.20);
        return Math.round(weighted);
    }

    get customerHealthScoreLabel() {
        const score = this.customerHealthScore;
        if (score >= 85) {
            return 'Excellent Momentum';
        }
        if (score >= 70) {
            return 'Healthy';
        }
        if (score >= 55) {
            return 'Watch';
        }
        return 'At Risk';
    }

    get customerHealthScoreClass() {
        const score = this.customerHealthScore;
        if (score >= 85) {
            return 'health-score excellent';
        }
        if (score >= 70) {
            return 'health-score healthy';
        }
        if (score >= 55) {
            return 'health-score watch';
        }
        return 'health-score risk';
    }

    get customerHealthStrokeDashoffset() {
        const circumference = 408.4; // 2 * pi * r where r=65
        const percent = Math.max(0, Math.min(100, this.customerHealthScore));
        return circumference - ((percent / 100) * circumference);
    }

    get customerHealthStrokeStyle() {
        return `stroke-dashoffset: ${this.customerHealthStrokeDashoffset};`;
    }

    get averageStars() {
        const avg = Number(this.summary?.averageRating || 0);
        return [1, 2, 3, 4, 5].map((value) => ({
            value,
            className: value <= Math.round(avg) ? 'star filled' : 'star'
        }));
    }

    get emojiButtons() {
        return this.emojiChoices.map((choice) => ({
            ...choice,
            className: choice.rating === this.selectedRating ? 'emoji active' : 'emoji'
        }));
    }

    get compliancePillClass() {
        const status = (this.summary?.heloc?.complianceStatus || '').toLowerCase();
        if (status === 'cleared') {
            return 'pill cleared';
        }
        if (status === 'blocked') {
            return 'pill blocked';
        }
        return 'pill pending';
    }

    get helocProgressPercent() {
        const limit = Number(this.summary?.heloc?.approvedLimit || 0);
        const drawn = Number(this.summary?.heloc?.amountDrawn || 0);
        if (!limit) {
            return 0;
        }
        return Math.min(100, Math.round((drawn / limit) * 100));
    }

    get helocProgressStyle() {
        return `width: ${this.helocProgressPercent}%;`;
    }

    get relationshipManagerInitials() {
        const name = this.summary?.relationshipManager || '';
        return name
            .split(' ')
            .filter(Boolean)
            .map((part) => part[0])
            .join('')
            .toUpperCase();
    }

    get customerInitials() {
        const name = this.summary?.customerName || '';
        return name
            .split(' ')
            .filter(Boolean)
            .map((part) => part[0])
            .join('')
            .toUpperCase();
    }

    get todayPartOfDay() {
        const hour = new Date().getHours();
        if (hour < 12) {
            return 'morning';
        }
        if (hour < 18) {
            return 'afternoon';
        }
        return 'evening';
    }

    get chartPath() {
        const base = [66, 64, 61, 58, 55, 51, 48, 43];
        return `M0 80 L ${base.map((y, i) => `${(i + 1) * 45} ${y}`).join(' L ')}`;
    }

    get trendText() {
        const monthly = this.summary?.monthlyChange || 0;
        const direction = monthly >= 0 ? 'up' : 'down';
        return `Your portfolio is ${direction} ${Math.abs(monthly).toLocaleString()} this month.`;
    }

    get selectedEmojiText() {
        const selected = this.emojiChoices.find((choice) => choice.rating === this.selectedRating);
        return selected ? selected.icon : 'Rate today\'s visit';
    }

    get complianceCommitmentClass() {
        return this.summary?.complianceCleared ? 'pill cleared' : 'pill blocked';
    }

    get complianceCommitmentText() {
        return this.summary?.complianceCleared ? 'ACTIVE' : 'NEEDS REVIEW';
    }

    handleRefresh() {
        if (this.wiredSummaryResult) {
            refreshApex(this.wiredSummaryResult);
        }
    }

    handleSelectRating(event) {
        this.selectedRating = Number(event.currentTarget.dataset.rating);
    }

    handleCommentChange(event) {
        this.feedbackText = event.target.value;
    }

    async handleSubmitFeedback() {
        if (!this.selectedRating || !this.resolvedCustomerId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Choose a rating',
                    message: 'Please select a rating before submitting feedback.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isSubmitting = true;
        try {
            await submitFeedback({
                customerId: this.resolvedCustomerId,
                rating: this.selectedRating,
                comments: this.feedbackText
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Thank you',
                    message: 'Your feedback has been saved.',
                    variant: 'success'
                })
            );
            this.feedbackText = '';
            this.selectedRating = 0;
            await refreshApex(this.wiredSummaryResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Feedback failed',
                    message: error?.body?.message || 'Unable to submit feedback at this time.',
                    variant: 'error'
                })
            );
        } finally {
            this.isSubmitting = false;
        }
    }
}