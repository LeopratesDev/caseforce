import { createElement } from 'lwc';
import { updateRecord } from 'lightning/uiRecordApi';
import CaseBoard from 'c/caseBoard';
import getCases from '@salesforce/apex/CaseBoardController.getCases';
import getMetrics from '@salesforce/apex/CaseBoardController.getMetrics';
import getFilterOptions from '@salesforce/apex/CaseBoardController.getFilterOptions';

jest.mock('@salesforce/apex/CaseBoardController.getCases', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/CaseBoardController.getMetrics', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/CaseBoardController.getFilterOptions', () => ({ default: jest.fn() }), { virtual: true });

const OPTIONS = {
    status: [
        { label: 'New', value: 'New' },
        { label: 'Escalated', value: 'Escalated' }
    ],
    priority: [{ label: 'High', value: 'High' }],
    category: [{ label: 'Billing', value: 'Billing' }]
};

const ROWS = [
    {
        id: '500000000000001AAA',
        caseNumber: '00001001',
        subject: 'Cobranca duplicada',
        status: 'New',
        priority: 'High',
        category: 'Billing',
        ownerName: 'Billing Support',
        escalationLevel: 0,
        resolutionDueAt: '2026-11-05T10:00:00.000Z',
        isOverdue: true
    },
    {
        id: '500000000000002AAA',
        caseNumber: '00001002',
        subject: 'Acesso bloqueado',
        status: 'Closed',
        priority: 'Low',
        category: 'Access',
        ownerName: 'Ana',
        escalationLevel: 1,
        resolutionDueAt: null,
        isOverdue: false
    }
];

// O stub do sfdx-lwc-jest exporta so a classe ShowToastEvent, nao o nome do evento.
const ShowToastEventName = 'lightning__showtoast';

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mountBoard() {
    const element = createElement('c-case-board', { is: CaseBoard });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

const table = (element) => element.shadowRoot.querySelector('lightning-datatable');
// getCases recebe os filtros como parametros soltos (um objeto chegava vazio ao Apex).
const lastFilters = () => getCases.mock.calls[getCases.mock.calls.length - 1][0];

describe('c-case-board', () => {
    beforeEach(() => {
        getCases.mockResolvedValue(ROWS);
        getMetrics.mockResolvedValue({ open: 7, escalated: 2, overdue: 3 });
        getFilterOptions.mockResolvedValue(OPTIONS);
        updateRecord.mockResolvedValue({});
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('shows the cases returned by Apex, with a link and overdue highlight', async () => {
        const element = await mountBoard();

        const data = table(element).data;
        expect(data).toHaveLength(2);
        expect(data[0].recordUrl).toBe('/lightning/r/Case/500000000000001AAA/view');
        expect(data[0].dueClass).toContain('slds-text-color_error');
        expect(data[1].dueClass).toBe('');
    });

    it('shows the SLA metrics', async () => {
        const element = await mountBoard();

        const value = (id) => element.shadowRoot.querySelector(`[data-id="${id}"] .tile-value`).textContent;
        expect(value('metric-open')).toBe('7');
        expect(value('metric-escalated')).toBe('2');
        expect(value('metric-overdue')).toBe('3');
    });

    it('fills the filter dropdowns with an "all" option plus the picklist values', async () => {
        const element = await mountBoard();

        const status = element.shadowRoot.querySelector('lightning-combobox[data-filter="status"]');
        expect(status.options.map((o) => o.value)).toEqual(['', 'New', 'Escalated']);
    });

    it('queries again with the chosen filter', async () => {
        const element = await mountBoard();

        const status = element.shadowRoot.querySelector('lightning-combobox[data-filter="status"]');
        status.dispatchEvent(new CustomEvent('change', { detail: { value: 'Escalated' } }));
        await flushPromises();

        expect(lastFilters().status).toBe('Escalated');
    });

    it('applies the overdue toggle', async () => {
        const element = await mountBoard();

        const toggle = element.shadowRoot.querySelector('[data-id="overdue-toggle"]');
        toggle.dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));
        await flushPromises();

        expect(lastFilters().onlyOverdue).toBe(true);
    });

    it('waits for the user to stop typing before searching', async () => {
        jest.useFakeTimers();
        const element = createElement('c-case-board', { is: CaseBoard });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();
        getCases.mockClear();

        const search = element.shadowRoot.querySelector('[data-id="search"]');
        search.dispatchEvent(new CustomEvent('change', { detail: { value: 'co' } }));
        search.dispatchEvent(new CustomEvent('change', { detail: { value: 'cobranca' } }));
        expect(getCases).not.toHaveBeenCalled();

        jest.advanceTimersByTime(300);
        await Promise.resolve();

        expect(getCases).toHaveBeenCalledTimes(1);
        expect(lastFilters().searchTerm).toBe('cobranca');
    });

    it('escalates a case from the row action and reloads', async () => {
        const element = await mountBoard();
        const toasts = [];
        element.addEventListener(ShowToastEventName, (e) => toasts.push(e.detail));
        getCases.mockClear();

        table(element).dispatchEvent(
            new CustomEvent('rowaction', { detail: { action: { name: 'escalate' }, row: ROWS[0] } })
        );
        await flushPromises();

        expect(updateRecord).toHaveBeenCalledWith({ fields: { Id: ROWS[0].id, Status: 'Escalated' } });
        expect(toasts[0].variant).toBe('success');
        expect(getCases).toHaveBeenCalledTimes(1);
    });

    it('assigns the case to the current user', async () => {
        const element = await mountBoard();

        table(element).dispatchEvent(
            new CustomEvent('rowaction', { detail: { action: { name: 'assume' }, row: ROWS[0] } })
        );
        await flushPromises();

        const { fields } = updateRecord.mock.calls[0][0];
        expect(fields.Id).toBe(ROWS[0].id);
        expect(fields.OwnerId).toBeTruthy();
    });

    it('does not escalate a closed case', async () => {
        const element = await mountBoard();
        const toasts = [];
        element.addEventListener(ShowToastEventName, (e) => toasts.push(e.detail));

        table(element).dispatchEvent(
            new CustomEvent('rowaction', { detail: { action: { name: 'escalate' }, row: ROWS[1] } })
        );
        await flushPromises();

        expect(updateRecord).not.toHaveBeenCalled();
        expect(toasts[0].variant).toBe('warning');
    });

    it('saves inline edits, one update per edited row', async () => {
        const element = await mountBoard();

        table(element).dispatchEvent(
            new CustomEvent('save', {
                detail: {
                    draftValues: [
                        { id: ROWS[0].id, subject: 'Novo assunto' },
                        { id: ROWS[1].id, subject: 'Outro assunto' }
                    ]
                }
            })
        );
        await flushPromises();

        expect(updateRecord).toHaveBeenCalledTimes(2);
        expect(updateRecord).toHaveBeenCalledWith({ fields: { Id: ROWS[0].id, Subject: 'Novo assunto' } });
        expect(table(element).draftValues).toEqual([]);
    });

    it('shows the Salesforce error when saving fails', async () => {
        updateRecord.mockRejectedValue({ body: { message: 'Informe o resumo da resolução.' } });
        const element = await mountBoard();
        const toasts = [];
        element.addEventListener(ShowToastEventName, (e) => toasts.push(e.detail));

        table(element).dispatchEvent(
            new CustomEvent('save', { detail: { draftValues: [{ id: ROWS[0].id, subject: 'x' }] } })
        );
        await flushPromises();

        expect(toasts[0].variant).toBe('error');
        expect(toasts[0].message).toBe('Informe o resumo da resolução.');
    });

    it('shows an empty state when nothing matches', async () => {
        getCases.mockResolvedValue([]);

        const element = await mountBoard();

        expect(table(element)).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    });

    it('shows the error when the query fails', async () => {
        getCases.mockRejectedValue({ body: { message: 'Sem acesso ao objeto Case.' } });

        const element = await mountBoard();

        expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toBe('Sem acesso ao objeto Case.');
        expect(table(element)).toBeNull();
    });
});
