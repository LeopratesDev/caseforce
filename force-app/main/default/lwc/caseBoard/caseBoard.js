import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { updateRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import getCases from '@salesforce/apex/CaseBoardController.getCases';
import getMetrics from '@salesforce/apex/CaseBoardController.getMetrics';
import getFilterOptions from '@salesforce/apex/CaseBoardController.getFilterOptions';

const SEARCH_DEBOUNCE_MS = 300;
const ALL_OPTION = { label: 'Todos', value: '' };

// Campo da tabela -> campo do Case, para as edicoes feitas direto na celula.
const EDITABLE_FIELDS = { subject: 'Subject' };

const COLUMNS = [
    {
        label: 'Caso',
        fieldName: 'recordUrl',
        type: 'url',
        initialWidth: 110,
        typeAttributes: { label: { fieldName: 'caseNumber' }, target: '_blank' }
    },
    { label: 'Assunto', fieldName: 'subject', editable: true },
    { label: 'Status', fieldName: 'status', initialWidth: 110 },
    {
        label: 'Prioridade',
        fieldName: 'priority',
        initialWidth: 115,
        cellAttributes: { class: { fieldName: 'priorityClass' } }
    },
    { label: 'Categoria', fieldName: 'category', initialWidth: 120 },
    { label: 'Dono', fieldName: 'ownerName', initialWidth: 160 },
    { label: 'Nível', fieldName: 'escalationLevel', type: 'number', initialWidth: 80 },
    {
        label: 'Vence em',
        fieldName: 'resolutionDueAt',
        type: 'date',
        initialWidth: 150,
        typeAttributes: { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' },
        cellAttributes: { class: { fieldName: 'dueClass' } }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Escalar', name: 'escalate' },
                { label: 'Assumir', name: 'assume' }
            ]
        }
    }
];

export default class CaseBoard extends LightningElement {
    columns = COLUMNS;
    rows = [];
    metrics = { open: 0, escalated: 0, overdue: 0 };
    filters = { status: '', priority: '', category: '', searchTerm: '', onlyOverdue: false };
    statusOptions = [ALL_OPTION];
    priorityOptions = [ALL_OPTION];
    categoryOptions = [ALL_OPTION];
    draftValues = [];
    isLoading = false;
    errorMessage;

    searchTimer;

    connectedCallback() {
        this.loadOptions();
        this.refresh();
    }

    disconnectedCallback() {
        clearTimeout(this.searchTimer);
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    async loadOptions() {
        try {
            const options = await getFilterOptions();
            this.statusOptions = [ALL_OPTION, ...options.status];
            this.priorityOptions = [ALL_OPTION, ...options.priority];
            this.categoryOptions = [ALL_OPTION, ...options.category];
        } catch (error) {
            this.errorMessage = reduceError(error);
        }
    }

    async refresh() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const [cases, metrics] = await Promise.all([getCases({ ...this.filters }), getMetrics()]);
            this.rows = cases.map(decorate);
            this.metrics = metrics;
        } catch (error) {
            this.errorMessage = reduceError(error);
            this.rows = [];
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.refresh();
    }

    handleFilterChange(event) {
        const field = event.target.dataset.filter;
        this.filters = { ...this.filters, [field]: event.detail.value };
        this.refresh();
    }

    handleOverdueToggle(event) {
        this.filters = { ...this.filters, onlyOverdue: event.detail.checked };
        this.refresh();
    }

    handleSearchChange(event) {
        const searchTerm = event.detail.value;
        clearTimeout(this.searchTimer);
        // Espera o usuario parar de digitar para nao consultar a cada tecla.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = setTimeout(() => {
            this.filters = { ...this.filters, searchTerm };
            this.refresh();
        }, SEARCH_DEBOUNCE_MS);
    }

    async handleSave(event) {
        const drafts = event.detail.draftValues;
        try {
            await Promise.all(
                drafts.map((draft) => {
                    const fields = { Id: draft.id };
                    Object.keys(EDITABLE_FIELDS).forEach((column) => {
                        if (column in draft) {
                            fields[EDITABLE_FIELDS[column]] = draft[column];
                        }
                    });
                    return updateRecord({ fields });
                })
            );
            this.draftValues = [];
            this.toast('Salvo', `${drafts.length} caso(s) atualizado(s).`, 'success');
            await this.refresh();
        } catch (error) {
            this.toast('Não foi possível salvar', reduceError(error), 'error');
        }
    }

    async handleRowAction(event) {
        const { action, row } = event.detail;
        if (row.status === 'Closed') {
            this.toast('Caso fechado', 'Casos fechados não podem ser escalados nem reatribuídos.', 'warning');
            return;
        }
        const changes = {
            escalate: { Status: 'Escalated' },
            assume: { OwnerId: USER_ID }
        }[action.name];
        if (!changes) {
            return;
        }
        try {
            await updateRecord({ fields: { Id: row.id, ...changes } });
            this.toast('Pronto', `Caso ${row.caseNumber} atualizado.`, 'success');
            await this.refresh();
        } catch (error) {
            this.toast('Não foi possível atualizar', reduceError(error), 'error');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

function decorate(row) {
    return {
        ...row,
        recordUrl: `/lightning/r/Case/${row.id}/view`,
        priorityClass: row.priority === 'High' ? 'slds-text-color_error slds-text-title_caps' : '',
        dueClass: row.isOverdue ? 'slds-text-color_error slds-text-title_caps' : ''
    };
}

function reduceError(error) {
    if (!error) {
        return 'Erro desconhecido.';
    }
    const body = error.body;
    if (Array.isArray(body)) {
        return body.map((e) => e.message).join(', ');
    }
    return body?.message || body?.output?.errors?.[0]?.message || error.message || 'Erro desconhecido.';
}
