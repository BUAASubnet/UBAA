import {
  FormExtensionAbility,
  formBindingData,
  formInfo,
  formProvider,
} from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { binding, forgetForm, rememberForm } from './HomeCardStore';

export default class HomeCardFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const parameters = want.parameters;
    const formId: Object | undefined =
      parameters === undefined
        ? undefined
        : parameters[formInfo.FormParam.IDENTITY_KEY];
    if (typeof formId === 'string') {
      rememberForm(this.context, formId);
    }
    return binding(this.context);
  }

  onUpdateForm(formId: string): void {
    formProvider.updateForm(formId, binding(this.context)).catch(() => {});
  }

  onRemoveForm(formId: string): void {
    forgetForm(this.context, formId);
  }
}
