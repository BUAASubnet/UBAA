import { HomeCardItem } from '../HomeCardStore';

interface CardAction {
  action: string;
  bundleName: string;
  abilityName: string;
}

const cardText: string = '#1B1B1F';
const cardSecondary: string = '#8A8A93';
const cardMuted: string = '#B0B0B8';
const cardAccent: string = '#0A59F7';
const cardAccentSoft: string = '#EAF1FF';
const cardViolet: string = '#6E4AEF';
const cardVioletSoft: string = '#F1EDFF';
const cardOrange: string = '#E8590C';
const cardOrangeSoft: string = '#FFF0E8';
const cardLine: string = '#EFEFF4';

let storage = new LocalStorage();

@Entry(storage)
@Component
struct HomeCardLarge {
  @LocalStorageProp('dateLabel') dateLabel: string = '';
  @LocalStorageProp('statusLine') statusLine: string = '';
  @LocalStorageProp('agendaLarge') agendaLarge: Array<HomeCardItem> = [];
  @LocalStorageProp('homework') homework: Array<HomeCardItem> = [];
  @LocalStorageProp('todo') todo: Array<HomeCardItem> = [];
  @LocalStorageProp('largeEmpty') largeEmpty: boolean = true;

  private openApp(): void {
    const action: CardAction = {
      action: 'router',
      bundleName: 'cn.edu.ubaa',
      abilityName: 'EntryAbility',
    };
    postCardAction(this, action);
  }

  @Builder
  sectionHeader(label: string, count: number, color: string, background: string) {
    Row() {
      Column()
        .width(6)
        .height(6)
        .backgroundColor(color)
        .borderRadius(3)
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(color)
        .margin({ left: 6 })
      Text(`${count}`)
        .fontSize(9)
        .fontColor(color)
        .backgroundColor(background)
        .borderRadius(7)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        .margin({ left: 5 })
      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 12, bottom: 2 })
  }

  @Builder
  section(label: string, items: Array<HomeCardItem>, color: string, background: string) {
    ListItem() {
      Column() {
        this.sectionHeader(label, items.length, color, background)
        Divider()
          .strokeWidth(1)
          .color(cardLine)
        ForEach(
          items,
          (item: HomeCardItem) => {
            Row() {
              Text(item.title)
                .fontSize(12)
                .fontColor(cardText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(item.time)
                .fontSize(10)
                .fontColor(color)
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ top: 5, bottom: 5 })
          },
          (item: HomeCardItem, index: number) => `${label}:${index}:${item.title}`,
        )
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Column() {
      Row() {
        Column() {
          Row() {
            Column()
              .width(4)
              .height(16)
              .backgroundColor(cardAccent)
              .borderRadius(2)
            Text('今日')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(cardText)
              .margin({ left: 8 })
          }
          .alignItems(VerticalAlign.Center)

          if (this.dateLabel.length > 0) {
            Text(this.dateLabel)
              .fontSize(10)
              .fontColor(cardSecondary)
              .margin({ top: 4, left: 12 })
          }
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.largeEmpty) {
        Column() {
          Text(this.statusLine)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardSecondary)
          Text('轻触打开 UBAA 同步今日安排')
            .fontSize(10)
            .fontColor(cardMuted)
            .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 18 })
      } else {
        List() {
          if (this.agendaLarge.length > 0) {
            this.section('日程', this.agendaLarge, cardAccent, cardAccentSoft)
          }
          if (this.homework.length > 0) {
            this.section('作业', this.homework, cardViolet, cardVioletSoft)
          }
          if (this.todo.length > 0) {
            this.section('待办', this.todo, cardOrange, cardOrangeSoft)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.openApp())
  }
}
