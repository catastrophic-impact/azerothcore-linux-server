SET
@Entry = 190012,
@Name = "Warpweaver";

DELETE FROM `creature_template` WHERE `entry` = @Entry;
INSERT INTO `creature_template` (`entry`, `name`, `subname`, `IconName`, `gossip_menu_id`, `minlevel`, `maxlevel`, `exp`, `faction`, `npcflag`, `rank`, `dmgschool`, `BaseAttackTime`, `RangeAttackTime`, `unit_class`, `unit_flags`, `type`, `type_flags`, `lootid`, `pickpocketloot`, `skinloot`, `AIName`, `MovementType`, `HoverHeight`, `RacialLeader`, `movementId`, `RegenHealth`, `CreatureImmunitiesId`, `flags_extra`, `ScriptName`) VALUES
(@Entry, @Name, "Transmogrifier", NULL, 0, 80, 80, 2, 35, 1, 0, 0, 2000, 0, 1, 0, 7, 138936390, 0, 0, 0, '', 0, 1, 0, 0, 1, 0, 0, 'npc_transmogrifier');

DELETE FROM `creature_template_model` WHERE `CreatureID` = @Entry;
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(@Entry, 0, 19646, 1, 1, 0);

DELETE FROM `creature_template_locale` WHERE `entry` = @Entry;
INSERT INTO `creature_template_locale` (`entry`, `locale`, `Name`, `Title`) VALUES
(@Entry, 'koKR', @Name, "변형기"),
(@Entry, 'frFR', @Name, "Transmogrificateur"),
(@Entry, 'deDE', @Name, "Transmogrifier"),
(@Entry, 'zhCN', @Name, "变形者"),
(@Entry, 'zhTW', @Name, "幻化大師"),
(@Entry, 'esES', @Name, "Transfigurador"),
(@Entry, 'esMX', @Name, "Transfigurador"),
(@Entry, 'ruRU', @Name, "Трансмогрификатор");

SET @GREETING := 601084;
DELETE FROM `npc_text` WHERE `ID` = @GREETING;
INSERT INTO `npc_text` (`ID`, `text0_0`) VALUES
(@GREETING, 'Greetings, $N. Do you wish to alter the appearance of your equipment?');

DELETE FROM `module_string` WHERE `module` = 'mod-transmog-plus';
INSERT INTO `module_string` (`module`, `id`, `string`) VALUES
('mod-transmog-plus', 1, 'Slot transmogrified.'),
('mod-transmog-plus', 2, 'Invalid source item.'),
('mod-transmog-plus', 3, 'All slot transmogs removed.'),
('mod-transmog-plus', 4, 'Slot hidden.'),
('mod-transmog-plus', 5, 'Slot transmog removed.'),
('mod-transmog-plus', 6, 'You do not have enough money.'),
('mod-transmog-plus', 7, 'Remove all transmogs'),
('mod-transmog-plus', 8, 'Remove all slot transmogs?'),
('mod-transmog-plus', 9, 'Back...'),
('mod-transmog-plus', 10, 'Hide slot'),
('mod-transmog-plus', 11, 'Remove transmog from slot'),
('mod-transmog-plus', 12, 'Next Page'),
('mod-transmog-plus', 13, 'Previous Page'),
('mod-transmog-plus', 14, 'No valid appearances found for this slot.'),
('mod-transmog-plus', 15, 'This item\'s appearance has been added to your collection.'),
('mod-transmog-plus', 16, 'Free'),
('mod-transmog-plus', 17, 'Equipment slot is empty.');

DELETE FROM `module_string_locale` WHERE `module` = 'mod-transmog-plus';
INSERT INTO `module_string_locale` (`module`, `id`, `locale`, `string`) VALUES
-- ID 1: OK
('mod-transmog-plus', 1, 'koKR', '슬롯이 형상변환되었습니다.'),
('mod-transmog-plus', 1, 'frFR', 'Emplacement transmogrifié.'),
('mod-transmog-plus', 1, 'deDE', 'Slot transmogrifiziert.'),
('mod-transmog-plus', 1, 'zhCN', '槽位已幻化。'),
('mod-transmog-plus', 1, 'zhTW', '欄位已幻化。'),
('mod-transmog-plus', 1, 'esES', 'Ranura transfigurada.'),
('mod-transmog-plus', 1, 'esMX', 'Ranura transfigurada.'),
('mod-transmog-plus', 1, 'ruRU', 'Ячейка трансмогрифицирована.'),
-- ID 2: INVALID_SRC
('mod-transmog-plus', 2, 'koKR', '잘못된 원본 아이템입니다.'),
('mod-transmog-plus', 2, 'frFR', 'Objet source non valide.'),
('mod-transmog-plus', 2, 'deDE', 'Ungültiger Quellgegenstand.'),
('mod-transmog-plus', 2, 'zhCN', '无效的源物品。'),
('mod-transmog-plus', 2, 'zhTW', '無效的來源物品。'),
('mod-transmog-plus', 2, 'esES', 'Objeto de origen no válido.'),
('mod-transmog-plus', 2, 'esMX', 'Objeto de origen no válido.'),
('mod-transmog-plus', 2, 'ruRU', 'Недопустимый исходный предмет.'),
-- ID 3: ALL_REMOVED
('mod-transmog-plus', 3, 'koKR', '모든 슬롯 형상변환이 제거되었습니다.'),
('mod-transmog-plus', 3, 'frFR', 'Toutes les transmogrifications d''emplacement ont été supprimées.'),
('mod-transmog-plus', 3, 'deDE', 'Alle Slot-Transmogrifikationen entfernt.'),
('mod-transmog-plus', 3, 'zhCN', '已移除所有槽位幻化。'),
('mod-transmog-plus', 3, 'zhTW', '已移除所有欄位幻化。'),
('mod-transmog-plus', 3, 'esES', 'Se eliminaron todas las transfiguraciones de ranura.'),
('mod-transmog-plus', 3, 'esMX', 'Se eliminaron todas las transfiguraciones de ranura.'),
('mod-transmog-plus', 3, 'ruRU', 'Все трансмогрификации ячеек удалены.'),
-- ID 4: HIDDEN
('mod-transmog-plus', 4, 'koKR', '슬롯이 숨겨졌습니다.'),
('mod-transmog-plus', 4, 'frFR', 'Emplacement masqué.'),
('mod-transmog-plus', 4, 'deDE', 'Slot verborgen.'),
('mod-transmog-plus', 4, 'zhCN', '槽位已隐藏。'),
('mod-transmog-plus', 4, 'zhTW', '欄位已隱藏。'),
('mod-transmog-plus', 4, 'esES', 'Ranura oculta.'),
('mod-transmog-plus', 4, 'esMX', 'Ranura oculta.'),
('mod-transmog-plus', 4, 'ruRU', 'Ячейка скрыта.'),
-- ID 5: SLOT_REMOVED
('mod-transmog-plus', 5, 'koKR', '슬롯 형상변환이 제거되었습니다.'),
('mod-transmog-plus', 5, 'frFR', 'Transmogrification d''emplacement supprimée.'),
('mod-transmog-plus', 5, 'deDE', 'Slot-Transmogrifikation entfernt.'),
('mod-transmog-plus', 5, 'zhCN', '已移除槽位幻化。'),
('mod-transmog-plus', 5, 'zhTW', '已移除欄位幻化。'),
('mod-transmog-plus', 5, 'esES', 'Transfiguración de ranura eliminada.'),
('mod-transmog-plus', 5, 'esMX', 'Transfiguración de ranura eliminada.'),
('mod-transmog-plus', 5, 'ruRU', 'Трансмогрификация ячейки удалена.'),
-- ID 6: NO_MONEY
('mod-transmog-plus', 6, 'koKR', '돈이 충분하지 않습니다.'),
('mod-transmog-plus', 6, 'frFR', 'Vous n''avez pas assez d''argent.'),
('mod-transmog-plus', 6, 'deDE', 'Du hast nicht genug Geld.'),
('mod-transmog-plus', 6, 'zhCN', '你没有足够的钱。'),
('mod-transmog-plus', 6, 'zhTW', '你沒有足夠的金錢。'),
('mod-transmog-plus', 6, 'esES', 'No tienes suficiente dinero.'),
('mod-transmog-plus', 6, 'esMX', 'No tienes suficiente dinero.'),
('mod-transmog-plus', 6, 'ruRU', 'У вас недостаточно денег.'),
-- ID 7: REMOVE_ALL
('mod-transmog-plus', 7, 'koKR', '모든 형상변환 제거'),
('mod-transmog-plus', 7, 'frFR', 'Supprimer toutes les transmogrifications'),
('mod-transmog-plus', 7, 'deDE', 'Alle Transmogrifikationen entfernen'),
('mod-transmog-plus', 7, 'zhCN', '移除所有幻化'),
('mod-transmog-plus', 7, 'zhTW', '移除所有幻化'),
('mod-transmog-plus', 7, 'esES', 'Eliminar todas las transfiguraciones'),
('mod-transmog-plus', 7, 'esMX', 'Eliminar todas las transfiguraciones'),
('mod-transmog-plus', 7, 'ruRU', 'Удалить все трансмогрификации'),
-- ID 8: REMOVE_ALL_ASK
('mod-transmog-plus', 8, 'koKR', '모든 슬롯 형상변환을 제거하시겠습니까?'),
('mod-transmog-plus', 8, 'frFR', 'Supprimer toutes les transmogrifications d''emplacement ?'),
('mod-transmog-plus', 8, 'deDE', 'Alle Slot-Transmogrifikationen entfernen?'),
('mod-transmog-plus', 8, 'zhCN', '要移除所有槽位幻化吗？'),
('mod-transmog-plus', 8, 'zhTW', '要移除所有欄位幻化嗎？'),
('mod-transmog-plus', 8, 'esES', '¿Eliminar todas las transfiguraciones de ranura?'),
('mod-transmog-plus', 8, 'esMX', '¿Eliminar todas las transfiguraciones de ranura?'),
('mod-transmog-plus', 8, 'ruRU', 'Удалить все трансмогрификации ячеек?'),
-- ID 9: BACK
('mod-transmog-plus', 9, 'koKR', '뒤로...'),
('mod-transmog-plus', 9, 'frFR', 'Retour...'),
('mod-transmog-plus', 9, 'deDE', 'Zurück...'),
('mod-transmog-plus', 9, 'zhCN', '返回...'),
('mod-transmog-plus', 9, 'zhTW', '返回...'),
('mod-transmog-plus', 9, 'esES', 'Atrás...'),
('mod-transmog-plus', 9, 'esMX', 'Atrás...'),
('mod-transmog-plus', 9, 'ruRU', 'Назад...'),
-- ID 10: HIDE_SLOT
('mod-transmog-plus', 10, 'koKR', '슬롯 숨기기'),
('mod-transmog-plus', 10, 'frFR', 'Masquer l''emplacement'),
('mod-transmog-plus', 10, 'deDE', 'Slot verbergen'),
('mod-transmog-plus', 10, 'zhCN', '隐藏槽位'),
('mod-transmog-plus', 10, 'zhTW', '隱藏欄位'),
('mod-transmog-plus', 10, 'esES', 'Ocultar ranura'),
('mod-transmog-plus', 10, 'esMX', 'Ocultar ranura'),
('mod-transmog-plus', 10, 'ruRU', 'Скрыть ячейку'),
-- ID 11: REMOVE_SLOT
('mod-transmog-plus', 11, 'koKR', '슬롯에서 형상변환 제거'),
('mod-transmog-plus', 11, 'frFR', 'Supprimer la transmogrification de l''emplacement'),
('mod-transmog-plus', 11, 'deDE', 'Transmogrifikation aus Slot entfernen'),
('mod-transmog-plus', 11, 'zhCN', '从槽位移除幻化'),
('mod-transmog-plus', 11, 'zhTW', '從欄位移除幻化'),
('mod-transmog-plus', 11, 'esES', 'Eliminar transfiguración de la ranura'),
('mod-transmog-plus', 11, 'esMX', 'Eliminar transfiguración de la ranura'),
('mod-transmog-plus', 11, 'ruRU', 'Удалить трансмогрификацию из ячейки'),
-- ID 12: NEXT_PAGE
('mod-transmog-plus', 12, 'koKR', '다음 페이지'),
('mod-transmog-plus', 12, 'frFR', 'Page suivante'),
('mod-transmog-plus', 12, 'deDE', 'Nächste Seite'),
('mod-transmog-plus', 12, 'zhCN', '下一页'),
('mod-transmog-plus', 12, 'zhTW', '下一頁'),
('mod-transmog-plus', 12, 'esES', 'Página siguiente'),
('mod-transmog-plus', 12, 'esMX', 'Página siguiente'),
('mod-transmog-plus', 12, 'ruRU', 'Следующая страница'),
-- ID 13: PREVIOUS_PAGE
('mod-transmog-plus', 13, 'koKR', '이전 페이지'),
('mod-transmog-plus', 13, 'frFR', 'Page précédente'),
('mod-transmog-plus', 13, 'deDE', 'Vorherige Seite'),
('mod-transmog-plus', 13, 'zhCN', '上一页'),
('mod-transmog-plus', 13, 'zhTW', '上一頁'),
('mod-transmog-plus', 13, 'esES', 'Página anterior'),
('mod-transmog-plus', 13, 'esMX', 'Página anterior'),
('mod-transmog-plus', 13, 'ruRU', 'Предыдущая страница'),
-- ID 14: NO_APPEARANCES
('mod-transmog-plus', 14, 'koKR', '이 슬롯에 대해 유효한 외형을 찾을 수 없습니다.'),
('mod-transmog-plus', 14, 'frFR', 'Aucune apparence valide trouvée pour cet emplacement.'),
('mod-transmog-plus', 14, 'deDE', 'Keine gültigen Erscheinungsbilder für diesen Slot gefunden.'),
('mod-transmog-plus', 14, 'zhCN', '未找到该槽位的有效外观。'),
('mod-transmog-plus', 14, 'zhTW', '找不到此欄位的有效外觀。'),
('mod-transmog-plus', 14, 'esES', 'No se encontraron apariencias válidas para esta ranura.'),
('mod-transmog-plus', 14, 'esMX', 'No se encontraron apariencias válidas para esta ranura.'),
('mod-transmog-plus', 14, 'ruRU', 'Для этой ячейки не найдено допустимых обликов.'),
-- ID 15: APPEARANCE_ADDED
('mod-transmog-plus', 15, 'koKR', '이 아이템의 외형이 컬렉션에 추가되었습니다.'),
('mod-transmog-plus', 15, 'frFR', 'L''apparence de cet objet a été ajoutée à votre collection.'),
('mod-transmog-plus', 15, 'deDE', 'Das Erscheinungsbild dieses Gegenstands wurde deiner Sammlung hinzugefügt.'),
('mod-transmog-plus', 15, 'zhCN', '该物品的外观已添加到您的收藏中。'),
('mod-transmog-plus', 15, 'zhTW', '該物品的外觀已加入您的收藏。'),
('mod-transmog-plus', 15, 'esES', 'La apariencia de este objeto se ha añadido a tu colección.'),
('mod-transmog-plus', 15, 'esMX', 'La apariencia de este objeto se ha agregado a tu colección.'),
('mod-transmog-plus', 15, 'ruRU', 'Облик этого предмета добавлен в вашу коллекцию.'),
-- ID 16: FREE
('mod-transmog-plus', 16, 'koKR', '무료'),
('mod-transmog-plus', 16, 'frFR', 'Gratuit'),
('mod-transmog-plus', 16, 'deDE', 'Kostenlos'),
('mod-transmog-plus', 16, 'zhCN', '免费'),
('mod-transmog-plus', 16, 'zhTW', '免費'),
('mod-transmog-plus', 16, 'esES', 'Gratis'),
('mod-transmog-plus', 16, 'esMX', 'Gratis'),
('mod-transmog-plus', 16, 'ruRU', 'Бесплатно'),
-- ID 17: EMPTY_SLOT
('mod-transmog-plus', 17, 'koKR', '장비 슬롯이 비어 있습니다.'),
('mod-transmog-plus', 17, 'frFR', 'L''emplacement d''équipement est vide.'),
('mod-transmog-plus', 17, 'deDE', 'Der Ausrüstungsplatz ist leer.'),
('mod-transmog-plus', 17, 'zhCN', '装备槽是空的。'),
('mod-transmog-plus', 17, 'zhTW', '裝備欄位是空的。'),
('mod-transmog-plus', 17, 'esES', 'La ranura de equipo está vacía.'),
('mod-transmog-plus', 17, 'esMX', 'La ranura de equipo está vacía.'),
('mod-transmog-plus', 17, 'ruRU', 'Слот снаряжения пуст.');
