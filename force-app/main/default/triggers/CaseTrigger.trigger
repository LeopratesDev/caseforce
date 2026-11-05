trigger CaseTrigger on Case (before insert, before update, after update) {
    CaseTriggerHandler.run();
}
